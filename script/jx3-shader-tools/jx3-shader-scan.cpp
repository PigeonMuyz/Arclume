// Build with C++17 and libzstd. This process only reads the installed cache and graphics DLLs.
// Usage: jx3-shader-scan --game-root /path/to/Game/JX3
// Stdout: "ARCLJX3S", LE u32 version 1, then (LE u32 size, DXBC bytes) records.
// LE u32 zero terminates a successful stream. Stderr carries JSON progress.
// Add --count-only to keep stdout empty and count all validated shader keys.
#include <zstd.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>

namespace {
namespace fs = std::filesystem;
using Byte = std::uint8_t;
using Bytes = std::vector<Byte>;

constexpr std::size_t shardHeaderSize = 16;
constexpr std::size_t recordHeaderSize = 23;
constexpr std::size_t recordAlignment = 256;
constexpr std::size_t indexRecordSize = 31;
constexpr std::size_t indexFooterSize = 16;
constexpr std::size_t maxCompressedSize = 16 * 1024 * 1024;
constexpr std::size_t maxDecodedSize = 32 * 1024 * 1024;
constexpr std::size_t maxRendererSize = 128 * 1024 * 1024;
constexpr std::array<Byte, 4> zstdMagic = {0x28, 0xb5, 0x2f, 0xfd};

std::uint64_t littleEndian(const Byte* data, unsigned size) {
    std::uint64_t result = 0;
    for (unsigned byte = 0; byte < size; ++byte) {
        result |= std::uint64_t(data[byte]) << (8 * byte);
    }
    return result;
}

std::uint32_t readU32(const Byte* data) {
    return static_cast<std::uint32_t>(littleEndian(data, 4));
}

bool containsRange(std::uint64_t length, std::uint64_t offset, std::size_t size) {
    return offset <= length && size <= length - offset;
}

class ArchiveFile {
public:
    explicit ArchiveFile(const fs::path& path) : name(path.filename().string()) {
        fd = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
        if (fd < 0) throw std::runtime_error("Cannot open " + name + ": " + std::strerror(errno));
        if (fstat(fd, &initial) != 0 || !S_ISREG(initial.st_mode) || initial.st_size <= 0) {
            close(fd);
            throw std::runtime_error("Invalid archive file " + name);
        }
    }

    ~ArchiveFile() { close(fd); }

    ArchiveFile(const ArchiveFile&) = delete;
    ArchiveFile& operator=(const ArchiveFile&) = delete;

    std::uint64_t size() const { return initial.st_size; }

    void read(std::uint64_t offset, Byte* result, std::size_t count) const {
        if (!containsRange(size(), offset, count)) throw std::runtime_error("Truncated " + name);
        while (count > 0) {
            const ssize_t received = pread(fd, result, count, static_cast<off_t>(offset));
            if (received < 0 && errno == EINTR) continue;
            if (received <= 0) throw std::runtime_error("Could not read " + name);
            offset += received;
            result += received;
            count -= received;
        }
    }

    void verifyUnchanged() const {
        struct stat current = {};
        if (fstat(fd, &current) != 0 || current.st_size != initial.st_size
            || current.st_mtimespec.tv_sec != initial.st_mtimespec.tv_sec
            || current.st_mtimespec.tv_nsec != initial.st_mtimespec.tv_nsec) {
            throw std::runtime_error(name + " changed while scanning. Finish game updates and retry.");
        }
    }

private:
    int fd;
    struct stat initial = {};
    std::string name;
};

struct ShaderKey {
    std::uint64_t digestLo;
    std::uint64_t digestHi;
    std::uint32_t stage;

    bool operator==(const ShaderKey& other) const {
        return digestLo == other.digestLo && digestHi == other.digestHi && stage == other.stage;
    }
};

struct ShaderKeyHash {
    std::size_t operator()(const ShaderKey& key) const {
        return key.digestLo ^ ((key.digestHi << 13) | (key.digestHi >> 51)) ^ key.stage;
    }
};

struct Shader {
    ShaderKey key = {};
    std::uint32_t size = 0;
};

// Validate the DXBC v1 container, part boundaries, and SM4/5 program header.
// The offline Direct3D compiler validates the actual tokens separately.
Shader parseShader(const Byte* data, std::size_t available) {
    constexpr std::size_t headerSize = 32;
    constexpr std::size_t maxParts = 64;
    if (available < headerSize || readU32(data + 20) != 1) return {};
    const auto size = readU32(data + 24);
    const auto partCount = readU32(data + 28);
    if (partCount == 0 || partCount > maxParts || size > available) return {};
    const std::size_t partsStart = headerSize + 4 * partCount;
    if (size < partsStart) return {};

    struct PartRange { std::uint32_t start, end; };
    std::array<PartRange, maxParts> ranges;
    std::uint32_t stage = 0;
    bool hasProgram = false;
    for (std::size_t i = 0; i < partCount; ++i) {
        const auto offset = readU32(data + headerSize + 4 * i);
        if (offset < partsStart || !containsRange(size, offset, 8)) return {};
        const Byte* part = data + offset;
        const auto partSize = readU32(part + 4);
        if (!containsRange(size, offset + 8, partSize)) return {};
        ranges[i] = {offset, offset + 8 + partSize};
        if (std::memcmp(part, "SHDR", 4) != 0 && std::memcmp(part, "SHEX", 4) != 0) continue;
        if (hasProgram || partSize < 8 || partSize % 4 != 0) return {};
        const auto token = readU32(part + 8);
        const auto majorVersion = (token >> 4) & 15;
        const auto words = readU32(part + 12);
        stage = token >> 16;
        if ((majorVersion != 4 && majorVersion != 5) || stage > 5
            || words < 2 || words != partSize / 4) return {};
        hasProgram = true;
    }
    if (!hasProgram) return {};
    std::sort(ranges.begin(), ranges.begin() + partCount,
              [](PartRange a, PartRange b) { return a.start < b.start; });
    for (std::size_t i = 1; i < partCount; ++i) {
        if (ranges[i - 1].end > ranges[i].start) return {};
    }
    return {{littleEndian(data + 4, 8), littleEndian(data + 12, 8), stage}, size};
}

void writeExact(const void* data, std::size_t size) {
    if (std::fwrite(data, 1, size, stdout) != size) throw std::runtime_error("Output stream is closed");
}

void writeU32(std::uint32_t value) {
    const std::array<Byte, 4> data = {
        Byte(value), Byte(value >> 8), Byte(value >> 16), Byte(value >> 24)
    };
    writeExact(data.data(), data.size());
}

struct IndexRecord {
    std::uint64_t offset;
    std::uint32_t size;
};

std::vector<IndexRecord> readIndex(const fs::path& path) {
    const ArchiveFile file(path);
    if (file.size() < indexRecordSize + indexFooterSize || file.size() > maxDecodedSize
        || (file.size() - indexFooterSize) % indexRecordSize != 0) {
        throw std::runtime_error("Unsupported index layout in " + path.filename().string());
    }
    Bytes bytes(file.size());
    file.read(0, bytes.data(), bytes.size());
    file.verifyUnchanged();
    const auto count = (bytes.size() - indexFooterSize) / indexRecordSize;
    std::vector<IndexRecord> records;
    records.reserve(count);
    for (std::size_t i = 0; i < count; ++i) {
        const Byte* record = bytes.data() + i * indexRecordSize;
        const auto offset = littleEndian(record + 16, 8);
        if (offset % recordAlignment != shardHeaderSize) {
            throw std::runtime_error("Unsupported record offset in " + path.filename().string());
        }
        records.push_back({offset, readU32(record + 24)});
    }
    std::sort(records.begin(), records.end(), [](IndexRecord a, IndexRecord b) { return a.offset < b.offset; });
    return records;
}

bool hasFrameMagic(const Byte* header) {
    return header[6] == 0x10 && std::equal(zstdMagic.begin(), zstdMagic.end(), header + recordHeaderSize);
}

bool isRendererLibrary(const fs::path& path) {
    auto name = path.filename().string();
    std::transform(name.begin(), name.end(), name.begin(), [](char c) {
        return c >= 'A' && c <= 'Z' ? static_cast<char>(c + ('a' - 'A')) : c;
    });
    if (name.size() < 5 || name.compare(name.size() - 4, 4, ".dll") != 0) return false;
    constexpr std::array vendorPrefixes = {"nvflex", "nvvolumetric", "tressfx", "ffx_", "fidelityfx"};
    if (std::any_of(vendorPrefixes.begin(), vendorPrefixes.end(), [&](const char* prefix) {
        return name.rfind(prefix, 0) == 0;
    })) return true;
    constexpr std::array rendererNames = {
        "kg3dcullsystemx64.dll", "kg3dengineadapterx64.dll", "kg3denginedx11ex64.dll",
        "kg3denginedx11x64.dll", "kg3denginex64.dll", "kg3dmaterialsystemx64.dll",
        "kg3dshaderlibraryx64.dll", "kg3d_fsr3dx11x64.dll", "kg3d_geometryx64.dll",
        "kg3d_imguix64.dll", "kg3d_materialsystemx64.dll", "kg3d_nvflexbodyx64.dll",
        "kg3d_openvdbx64.dll", "kg3d_shaderreflectionx64.dll", "kg3d_tressfxx64.dll",
        "kg3d_trueskyx64.dll"
    };
    return std::find(rendererNames.begin(), rendererNames.end(), name) != rendererNames.end();
}

class Scanner {
public:
    Scanner(std::size_t count, bool countOnly) : totalShards(count), emitsBytecode(!countOnly) {
        if (!zstd) throw std::runtime_error("Could not allocate the Zstandard decoder");
    }

    void scan(const fs::path& shard, bool isLast) {
        const ArchiveFile file(shard);
        std::array<Byte, shardHeaderSize + recordHeaderSize + zstdMagic.size()> header;
        file.read(0, header.data(), header.size());
        const auto layout = readU32(header.data() + 8);
        if ((layout != 0 && layout != 2) || !hasFrameMagic(header.data() + shardHeaderSize)) {
            throw std::runtime_error("Unsupported Pakv4 shard header in " + shard.filename().string());
        }
        auto index = shard;
        index.replace_extension(".idx");
        if (fs::exists(index)) {
            for (const auto& record : readIndex(index)) scanRecord(file, shard, record);
        } else if (isLast) {
            scanAligned(file, shard);
        } else {
            throw std::runtime_error("Missing shader archive index " + index.filename().string());
        }
        file.verifyUnchanged();
        ++shardsCompleted;
        report("progress");
    }

    void scanRenderers(const fs::path& root) {
        const auto directory = root / "bin" / "zhcn_hd" / "bin64";
        if (!fs::is_directory(directory)) return;
        std::vector<fs::path> renderers;
        for (const auto& entry : fs::directory_iterator(directory)) {
            if (isRendererLibrary(entry.path())) renderers.push_back(entry.path());
        }
        std::sort(renderers.begin(), renderers.end());
        for (const auto& renderer : renderers) {
            const auto before = shaders.size();
            scanRenderer(renderer);
            ++rendererFilesScanned;
            rendererShadersAdded += shaders.size() - before;
            if (std::chrono::steady_clock::now() >= nextProgress) report("progress");
        }
    }

    void report(const char* event) {
        std::fprintf(stderr,
            "{\"event\":\"%s\",\"shardsCompleted\":%zu,\"totalShards\":%zu,"
            "\"shaderCount\":%zu,\"skippedFrames\":%zu,\"decodedFrames\":%zu,"
            "\"rendererFilesScanned\":%zu,\"rendererShadersAdded\":%zu}\n",
            event, shardsCompleted, totalShards, shaders.size(), skippedFrames, decodedFrames,
            rendererFilesScanned, rendererShadersAdded);
        std::fflush(stderr);
        nextProgress = std::chrono::steady_clock::now() + std::chrono::seconds(1);
    }

    bool empty() const { return shaders.empty(); }

private:
    void scanRenderer(const fs::path& library) {
        const ArchiveFile file(library);
        const auto invalid = [&] { return std::runtime_error("Invalid renderer PE " + library.filename().string()); };
        if (file.size() < 64 || file.size() > maxRendererSize) throw invalid();
        Bytes data(file.size());
        file.read(0, data.data(), data.size());
        file.verifyUnchanged();
        const auto peOffset = readU32(data.data() + 60);
        if (std::memcmp(data.data(), "MZ", 2) != 0 || !containsRange(data.size(), peOffset, 24)
            || std::memcmp(data.data() + peOffset, "PE\0\0", 4) != 0) throw invalid();
        const Byte* pe = data.data() + peOffset;
        const auto sectionCount = littleEndian(pe + 6, 2);
        const auto table = std::uint64_t(peOffset) + 24 + littleEndian(pe + 20, 2);
        constexpr std::size_t sectionSize = 40;
        if (sectionCount == 0 || !containsRange(data.size(), table, sectionCount * sectionSize)) throw invalid();
        for (std::size_t i = 0; i < sectionCount; ++i) {
            const auto* section = data.data() + table + i * sectionSize;
            const auto size = readU32(section + 16);
            const auto offset = readU32(section + 20);
            if (size == 0) continue;
            if (!containsRange(data.size(), offset, size)) throw invalid();
            scanShaders(data.data() + offset, size);
        }
    }

    void scanAligned(const ArchiveFile& file, const fs::path& shard) {
        constexpr std::size_t blockSize = 4 * 1024 * 1024;
        constexpr std::size_t probeSize = recordHeaderSize + zstdMagic.size();
        Bytes block(blockSize);
        for (std::uint64_t at = shardHeaderSize; at < file.size(); at += blockSize) {
            const auto size = static_cast<std::size_t>(std::min<std::uint64_t>(blockSize, file.size() - at));
            file.read(at, block.data(), size);
            for (std::size_t offset = 0; offset + probeSize <= size; offset += recordAlignment) {
                const Byte* candidate = block.data() + offset;
                if (hasFrameMagic(candidate)) scanRecord(file, shard, {at + offset, readU32(candidate)});
            }
        }
    }

    void scanRecord(const ArchiveFile& file, const fs::path& shard, IndexRecord record) {
        // The published cache has one stale indexed record with only 8 bytes.
        if (record.size == 8) {
            ++skippedFrames;
            return;
        }
        const auto fail = [&] {
            return std::runtime_error("Invalid Zstandard record at byte " + std::to_string(record.offset)
                                      + " in " + shard.filename().string());
        };
        if (record.size < zstdMagic.size() || record.size > maxCompressedSize
            || !containsRange(file.size(), record.offset, recordHeaderSize + record.size)) throw fail();
        encoded.resize(recordHeaderSize + record.size);
        file.read(record.offset, encoded.data(), encoded.size());
        if (readU32(encoded.data()) != record.size || !hasFrameMagic(encoded.data())) throw fail();
        const Byte* frame = encoded.data() + recordHeaderSize;
        const auto decodedSize = ZSTD_getFrameContentSize(frame, record.size);
        if (!decodedSize || decodedSize > maxDecodedSize
            || ZSTD_findFrameCompressedSize(frame, record.size) != record.size) throw fail();
        decoded.resize(static_cast<std::size_t>(decodedSize));
        if (ZSTD_decompressDCtx(zstd.get(), decoded.data(), decoded.size(), frame, record.size) != decoded.size()) {
            throw fail();
        }
        ++decodedFrames;
        scanShaders(decoded.data(), decoded.size());
        if (std::chrono::steady_clock::now() >= nextProgress) report("progress");
    }

    void scanShaders(const Byte* data, std::size_t size) {
        const Byte* cursor = data;
        const Byte* end = data + size;
        while (end - cursor >= 32) {
            const auto* candidate = static_cast<const Byte*>(std::memchr(cursor, 'D', end - cursor - 31));
            if (!candidate) break;
            cursor = candidate + 1;
            if (std::memcmp(candidate, "DXBC", 4) != 0) continue;
            const auto shader = parseShader(candidate, end - candidate);
            if (!shader.size) continue;
            // DXVK uses the original container digest and stage for ordinary shader keys.
            if (shaders.insert(shader.key).second && emitsBytecode) {
                writeU32(shader.size);
                writeExact(candidate, shader.size);
            }
            cursor = candidate + shader.size;
        }
    }

    std::unique_ptr<ZSTD_DCtx, decltype(&ZSTD_freeDCtx)> zstd{ZSTD_createDCtx(), ZSTD_freeDCtx};
    Bytes encoded, decoded;
    std::unordered_set<ShaderKey, ShaderKeyHash> shaders;
    const std::size_t totalShards;
    const bool emitsBytecode;
    std::size_t shardsCompleted = 0, skippedFrames = 0, decodedFrames = 0;
    std::size_t rendererFilesScanned = 0, rendererShadersAdded = 0;
    std::chrono::steady_clock::time_point nextProgress;
};

std::vector<fs::path> listShards(const fs::path& root) {
    const auto archive = root / "Pakv4" / "1033";
    std::vector<fs::path> shards;
    for (const auto& entry : fs::directory_iterator(archive)) {
        const auto stem = entry.path().stem().string();
        if (entry.path().extension() == ".dat" && stem.size() == 3
            && std::all_of(stem.begin(), stem.end(), [](char c) { return c >= '0' && c <= '9'; })) {
            shards.push_back(entry.path());
        }
    }
    std::sort(shards.begin(), shards.end());
    if (shards.empty()) throw std::runtime_error("The installed Pakv4/1033 shader archive is missing");
    for (std::size_t i = 0; i < shards.size(); ++i) {
        if (static_cast<std::size_t>(std::stoi(shards[i].stem().string())) != i) {
            throw std::runtime_error("The installed shader archive is missing a shard");
        }
    }
    return shards;
}

void reportError(const char* message) {
    std::fputs("{\"event\":\"error\",\"message\":\"", stderr);
    for (; *message; ++message) {
        const auto byte = static_cast<unsigned char>(*message);
        if (byte < 0x20 || byte == 0x7f) std::fputc(' ', stderr);
        else {
            if (byte == '\\' || byte == '"') std::fputc('\\', stderr);
            std::fputc(byte, stderr);
        }
    }
    std::fputs("\"}\n", stderr);
}
} // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::strcmp(argv[1], "--help") == 0) {
            std::fputs("Usage: jx3-shader-scan [--count-only] --game-root /path/to/Game/JX3\n", stderr);
            return 0;
        }
        bool countOnly = false;
        fs::path gameRoot;
        for (int argument = 1; argument < argc; ++argument) {
            if (std::strcmp(argv[argument], "--count-only") == 0 && !countOnly) {
                countOnly = true;
            } else if (std::strcmp(argv[argument], "--game-root") == 0 && gameRoot.empty()
                       && argument + 1 < argc && argv[argument + 1][0]) {
                gameRoot = argv[++argument];
            } else {
                throw std::runtime_error("Usage: jx3-shader-scan [--count-only] --game-root /path/to/Game/JX3");
            }
        }
        if (gameRoot.empty()) throw std::runtime_error("A JX3 game root is required");
        const auto shards = listShards(gameRoot);
        constexpr std::size_t outputBufferSize = 1024 * 1024;
        static std::array<char, outputBufferSize> outputBuffer;
        std::setvbuf(stdout, outputBuffer.data(), _IOFBF, outputBuffer.size());
        Scanner scanner(shards.size(), countOnly);
        if (!countOnly) {
            writeExact("ARCLJX3S", 8);
            writeU32(1);
        }
        scanner.report("progress");
        for (std::size_t i = 0; i < shards.size(); ++i) scanner.scan(shards[i], i + 1 == shards.size());
        scanner.scanRenderers(gameRoot);
        if (scanner.empty()) throw std::runtime_error("The installed shader sources have no supported DXBC programs");
        if (!countOnly) writeU32(0);
        if (std::fflush(stdout) != 0) throw std::runtime_error("Output stream is closed");
        scanner.report("complete");
    } catch (const std::exception& error) {
        reportError(error.what());
        return 1;
    }
    return 0;
}
