// SPDX-License-Identifier: MIT
// The pinned DXMT interface declarations below derive from DXMT v0.80,
// commit 589adb780354b461645b29999cefaf533594ee99.
// Copyright (c) 2023 Feifan He. The DXMT MIT license ships with the tools.
#include <windows.h>
#include <bcrypt.h>
#include <d3d11.h>
#include <fcntl.h>
#include <io.h>

#include <array>
#include <charconv>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <memory>
#include <utility>
#include <variant>
#include <vector>

namespace dxmt080 {

class Shader;
struct Default {};
struct Vertex { void* layout; std::uint32_t passthrough; bool rasterizationDisabled; };
struct Pixel { std::uint32_t sampleMask; bool dualSource; bool disableDepth; std::uint32_t unormOutputs; };
struct TessellationVertexHull { void* layout; Shader* vertex; std::uint32_t indexFormat; std::uint32_t maxFactor; };
struct TessellationDomain { Shader* hull; std::uint32_t passthrough; std::uint32_t maxFactor; bool rasterizationDisabled; };
struct VertexStreamOutput { void* layout; std::uint64_t streamOutputLayout; };
struct GeometryVertex { void* layout; Shader* geometry; std::uint32_t indexFormat; bool strip; };
struct Geometry { Shader* vertex; bool strip; };
using Variant = std::variant<Default, Vertex, Pixel, TessellationVertexHull,
    TessellationDomain, VertexStreamOutput, GeometryVertex, Geometry>;
static_assert(sizeof(Variant) == 32 && alignof(Variant) == 8);

struct Function { std::uint64_t handle; };

class Work {
public:
    virtual ~Work() {}
    virtual Work* RunThreadpoolWork() = 0;
    virtual bool GetIsDone() = 0;
    virtual void SetIsDone(bool) = 0;
};

class CompiledShader : public Work {
public:
    virtual ~CompiledShader() {}
    virtual bool GetShader(Function*) = 0;
};

class Shader {
public:
    virtual ~Shader() {}
    virtual void* handle() = 0;
    virtual void* reflection() = 0;
    virtual void* constantBuffers() = 0;
    virtual void* arguments() = 0;
    virtual CompiledShader* get_shader(Variant) = 0;
};

struct ShaderInterface : IUnknown {
    virtual Shader* GetManagedShader() = 0;
};

constexpr GUID ShaderInterfaceID{
    0xe95ba1c7, 0xe43f, 0x49c3, {0xa9, 0x07, 0x4a, 0xc6, 0x69, 0xc9, 0xfb, 0x42}
};

} // namespace dxmt080

namespace {

constexpr std::uint32_t MaxShaderBytes = 16 * 1024 * 1024;
constexpr std::uint64_t DeviceBatchSize = 256;
constexpr std::uint64_t ProgressInterval = 16;
constexpr unsigned MaxWorkers = 16;
constexpr ULONGLONG CompileTimeoutMilliseconds = 30'000;
constexpr std::array<unsigned char, 32> DXMTModuleSHA256{
    0x7c, 0xa3, 0x82, 0xaf, 0x0e, 0xb3, 0x2d, 0x8a, 0x43, 0x2f, 0x6e, 0xfb, 0x14, 0xd5, 0x94, 0xfe,
    0xfb, 0x45, 0x67, 0x36, 0x63, 0xbe, 0x1f, 0x7e, 0x66, 0x82, 0x25, 0x4b, 0xff, 0x88, 0x5c, 0x47
};

struct ReleaseCOM {
    template<typename T> void operator()(T* value) const { value->Release(); }
};
template<typename T> using COMPtr = std::unique_ptr<T, ReleaseCOM>;
using Bytecode = std::vector<unsigned char>;

struct Counts {
    std::uint64_t processed = 0;
    std::uint64_t compiled = 0;
    std::uint64_t failed = 0;
    std::uint64_t unsupported = 0;
    std::uint64_t variants = 0;
    std::array<std::uint64_t, 6> stages{};
};

int error(const char* reason, HRESULT result = S_OK) {
    std::printf("{\"event\":\"error\",\"reason\":\"%s\",\"hresult\":\"0x%08lx\"}\n",
        reason, static_cast<unsigned long>(result));
    return 1;
}

void progress(const char* event, const Counts& counts) {
    std::printf("{\"event\":\"%s\",\"processed\":%llu,\"compiled\":%llu,\"failed\":%llu,"
        "\"unsupported\":%llu,\"variants\":%llu,\"stages\":[%llu,%llu,%llu,%llu,%llu,%llu]}\n",
        event, static_cast<unsigned long long>(counts.processed),
        static_cast<unsigned long long>(counts.compiled), static_cast<unsigned long long>(counts.failed),
        static_cast<unsigned long long>(counts.unsupported), static_cast<unsigned long long>(counts.variants),
        static_cast<unsigned long long>(counts.stages[0]), static_cast<unsigned long long>(counts.stages[1]),
        static_cast<unsigned long long>(counts.stages[2]), static_cast<unsigned long long>(counts.stages[3]),
        static_cast<unsigned long long>(counts.stages[4]), static_cast<unsigned long long>(counts.stages[5]));
}

std::uint32_t uint32LE(const unsigned char* bytes) {
    return std::uint32_t(bytes[0]) | (std::uint32_t(bytes[1]) << 8)
        | (std::uint32_t(bytes[2]) << 16) | (std::uint32_t(bytes[3]) << 24);
}

bool readLength(std::uint32_t& length) {
    std::array<unsigned char, 4> bytes{};
    if (std::fread(bytes.data(), 1, bytes.size(), stdin) != bytes.size()) return false;
    length = uint32LE(bytes.data());
    return true;
}

// DXBC SHDR/SHEX uses pixel, vertex, geometry, hull, domain, compute ordering.
int stageOf(const Bytecode& bytes) {
    if (bytes.size() < 36 || std::memcmp(bytes.data(), "DXBC", 4)
        || uint32LE(bytes.data() + 20) != 1 || uint32LE(bytes.data() + 24) != bytes.size()) return -1;
    const auto chunks = uint32LE(bytes.data() + 28);
    if (!chunks || chunks > (bytes.size() - 32) / 4) return -1;
    int result = -1;
    for (std::uint32_t index = 0; index < chunks; ++index) {
        const auto offset = uint32LE(bytes.data() + 32 + 4 * index);
        if (offset < 32 + chunks * 4 || offset > bytes.size() - 8) return -1;
        const auto chunk = bytes.data() + offset;
        const auto length = uint32LE(chunk + 4);
        if (length > bytes.size() - offset - 8) return -1;
        if (std::memcmp(chunk, "SHDR", 4) && std::memcmp(chunk, "SHEX", 4)) continue;
        if (length < 8 || result >= 0) return -1;
        const auto token = uint32LE(chunk + 8);
        const auto words = uint32LE(chunk + 12);
        const auto major = (token >> 4) & 0xf;
        const auto minor = token & 0xf;
        if ((major != 4 && major != 5) || (major == 4 && minor > 1) || (major == 5 && minor)
            || words < 2 || words > length / 4 || token >> 16 > 5) return -1;
        result = static_cast<int>(token >> 16);
    }
    return result;
}

bool verifyDXMTModule() {
    const auto module = GetModuleHandleW(L"d3d11.dll");
    if (!module) return false;
    const auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(module);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) return false;
    const auto pe = reinterpret_cast<const IMAGE_NT_HEADERS64*>(
        reinterpret_cast<const unsigned char*>(module) + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->OptionalHeader.SizeOfImage != 0x0037c000
        || pe->OptionalHeader.CheckSum != 0x0051f87d
        || pe->OptionalHeader.AddressOfEntryPoint != 0x11f0) return false;
    std::array<wchar_t, 32768> path{};
    const auto pathSize = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (!pathSize || pathSize >= path.size()) return false;
    const auto file = CreateFileW(path.data(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    bool okay = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
    if (okay) okay = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0;
    std::array<unsigned char, 65536> buffer{};
    DWORD size = 0;
    while (okay) {
        okay = ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &size, nullptr);
        if (!okay || !size) break;
        okay = BCryptHashData(hash, buffer.data(), size, 0) >= 0;
    }
    std::array<unsigned char, 32> digest{};
    if (okay) okay = BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0;
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    CloseHandle(file);
    return okay && digest == DXMTModuleSHA256;
}

template<typename Shader>
HRESULT create(ID3D11Device& device, const Bytecode& bytes, IUnknown** object,
    HRESULT (STDMETHODCALLTYPE ID3D11Device::*method)(const void*, SIZE_T, ID3D11ClassLinkage*, Shader**)) {
    Shader* result = nullptr;
    const auto status = (device.*method)(bytes.data(), bytes.size(), nullptr, &result);
    *object = result;
    return status;
}

HRESULT create(ID3D11Device& device, int stage, const Bytecode& bytes, IUnknown** object) {
    switch (stage) {
        case 0: return create(device, bytes, object, &ID3D11Device::CreatePixelShader);
        case 1: return create(device, bytes, object, &ID3D11Device::CreateVertexShader);
        case 2: return create(device, bytes, object, &ID3D11Device::CreateGeometryShader);
        case 3: return create(device, bytes, object, &ID3D11Device::CreateHullShader);
        case 4: return create(device, bytes, object, &ID3D11Device::CreateDomainShader);
        case 5: return create(device, bytes, object, &ID3D11Device::CreateComputeShader);
    }
    return E_INVALIDARG;
}

enum class ShaderResult { compiled, failed, unsupported };

void finishShader(Counts& counts, int stage, ShaderResult result) {
    ++counts.processed;
    if (stage >= 0) ++counts.stages[stage];
    switch (result) {
        case ShaderResult::compiled: ++counts.compiled; break;
        case ShaderResult::failed: ++counts.failed; break;
        case ShaderResult::unsupported: ++counts.unsupported; break;
    }
    if (counts.processed % ProgressInterval == 0) progress("progress", counts);
}

struct PendingShader {
    COMPtr<dxmt080::ShaderInterface> owner;
    dxmt080::Shader* shader;
    int stage;
    unsigned variantCount;
    unsigned variantIndex = 0;
    dxmt080::CompiledShader* task = nullptr;
    ULONGLONG deadline = 0;

    dxmt080::Variant variant() const {
        if (stage == 5) return dxmt080::Default{};
        if (stage == 1) return dxmt080::Vertex{nullptr, 0, false};
        // All boolean/UNORM combinations for the default sample mask.
        return dxmt080::Pixel{UINT32_MAX, bool(variantIndex & 1), bool(variantIndex & 2), variantIndex / 4};
    }

    bool submitVariant() {
        task = shader->get_shader(variant());
        deadline = GetTickCount64() + CompileTimeoutMilliseconds;
        return task != nullptr;
    }
};

// DXMT schedules compilation on its own workers and performs each SQLite write
// synchronously under its cache mutex. Submit from one thread because the
// per-shader variant map is not synchronized, and keep one job per slot.
bool waitForShader(std::vector<PendingShader>& pending, Counts& counts) {
    while (!pending.empty()) {
        bool finished = false;
        for (auto entry = pending.begin(); entry != pending.end();) {
            dxmt080::Function function{};
            if (!entry->task->GetShader(&function)) {
                if (GetTickCount64() >= entry->deadline) return false;
                ++entry;
                continue;
            }
            auto result = ShaderResult::failed;
            if (function.handle) {
                ++counts.variants;
                if (++entry->variantIndex == entry->variantCount) result = ShaderResult::compiled;
                else if (entry->submitVariant()) {
                    ++entry;
                    continue;
                }
            }
            finishShader(counts, entry->stage, result);
            entry = pending.erase(entry);
            finished = true;
        }
        if (finished) return true;
        Sleep(2);
    }
    return true;
}

[[noreturn]] void abortOnCompileTimeout() {
    // The pinned interface has no cancellation. Releasing the device while
    // DXMT is still compiling could destroy objects used by its workers.
    const auto status = error("shader-compile-timeout");
    TerminateProcess(GetCurrentProcess(), status);
    std::_Exit(status);
}

bool parseArguments(int argc, char** argv, bool& pixelVariants, unsigned& workers) {
    bool workerCountSpecified = false;
    for (int index = 1; index < argc; ++index) {
        if (std::strcmp(argv[index], "--pixel-variants") == 0 && !pixelVariants) {
            pixelVariants = true;
        } else if (std::strcmp(argv[index], "--workers") == 0 && !workerCountSpecified && index + 1 < argc) {
            workerCountSpecified = true;
            const char* value = argv[++index];
            const char* end = value + std::strlen(value);
            const auto parsed = std::from_chars(value, end, workers);
            if (parsed.ec != std::errc{} || parsed.ptr != end || !workers || workers > MaxWorkers) return false;
        } else {
            return false;
        }
    }
    SYSTEM_INFO system{};
    GetSystemInfo(&system);
    if (system.dwNumberOfProcessors && workers > system.dwNumberOfProcessors) workers = system.dwNumberOfProcessors;
    return true;
}

} // namespace

int main(int argc, char** argv) {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    bool pixelVariants = false;
    unsigned workers = 1;
    if (!parseArguments(argc, argv, pixelVariants, workers)) return error("invalid-arguments");
    if (_setmode(_fileno(stdin), _O_BINARY) == -1) return error("stdin-mode");
    std::array<char, 8> magic{};
    std::uint32_t version = 0;
    if (std::fread(magic.data(), 1, magic.size(), stdin) != magic.size()
        || std::memcmp(magic.data(), "ARCLJX3S", magic.size()) || !readLength(version) || version != 1) {
        return error("invalid-stream-header");
    }
    if (!verifyDXMTModule()) return error("dxmt-080-module-mismatch");
    std::array<wchar_t, 32768> cachePath{};
    const auto pathLength = GetEnvironmentVariableW(
        L"DXMT_SHADER_CACHE_PATH", cachePath.data(), static_cast<DWORD>(cachePath.size()));
    if (!pathLength || pathLength >= cachePath.size() || cachePath.front() != L'/') {
        return error("missing-absolute-darwin-cache-path");
    }
    std::array<wchar_t, 16> cacheSwitch{};
    if (GetEnvironmentVariableW(L"DXMT_SHADER_CACHE", cacheSwitch.data(), static_cast<DWORD>(cacheSwitch.size()))
        && std::wcscmp(cacheSwitch.data(), L"0") == 0) return error("dxmt-cache-disabled");

    Counts counts;
    COMPtr<ID3D11Device> device;
    Bytecode bytes;
    std::vector<PendingShader> pending;
    pending.reserve(workers);
    unsigned recordsInBatch = 0;
    const char* streamError = nullptr;
    HRESULT streamErrorStatus = S_OK;
    for (;;) {
        if (recordsInBatch == DeviceBatchSize) {
            while (!pending.empty()) if (!waitForShader(pending, counts)) abortOnCompileTimeout();
            device.reset();
            recordsInBatch = 0;
        } else if (pending.size() == workers && !waitForShader(pending, counts)) {
            abortOnCompileTimeout();
        }
        std::uint32_t size = 0;
        if (!readLength(size)) {
            streamError = "missing-stream-terminator";
            break;
        }
        if (!size) break;
        if (size > MaxShaderBytes) {
            streamError = "shader-too-large";
            break;
        }
        bytes.resize(size);
        if (std::fread(bytes.data(), 1, size, stdin) != size) {
            streamError = "truncated-shader";
            break;
        }
        ++recordsInBatch;
        const int stage = stageOf(bytes);
        if (stage < 0) {
            finishShader(counts, stage, ShaderResult::failed);
            continue;
        }
        if (!device) {
            ID3D11Device* result = nullptr;
            const auto feature = D3D_FEATURE_LEVEL_11_1;
            const auto status = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
                &feature, 1, D3D11_SDK_VERSION, &result, nullptr, nullptr);
            device.reset(result);
            if (FAILED(status) || !device) return error("create-device", status);
        }
        IUnknown* result = nullptr;
        const auto status = create(*device, stage, bytes, &result);
        COMPtr<IUnknown> object(result);
        if (FAILED(status) || !object) {
            finishShader(counts, stage, ShaderResult::failed);
        } else if (stage >= 2 && stage <= 4) {
            finishShader(counts, stage, ShaderResult::unsupported);
        } else {
            dxmt080::ShaderInterface* internal = nullptr;
            const auto queried = object->QueryInterface(dxmt080::ShaderInterfaceID, reinterpret_cast<void**>(&internal));
            COMPtr<dxmt080::ShaderInterface> internalShader(internal);
            if (FAILED(queried) || !internalShader) {
                streamError = "dxmt-internal-interface-mismatch";
                streamErrorStatus = queried;
                break;
            }
            auto managed = internalShader->GetManagedShader();
            if (managed) {
                const unsigned variantCount = stage == 0 && pixelVariants ? 64 : 1;
                PendingShader shader{std::move(internalShader), managed, stage, variantCount};
                if (shader.submitVariant()) {
                    pending.push_back(std::move(shader));
                    continue;
                }
            }
            finishShader(counts, stage, ShaderResult::failed);
        }
    }
    while (!pending.empty()) if (!waitForShader(pending, counts)) abortOnCompileTimeout();
    device.reset();
    if (streamError) return error(streamError, streamErrorStatus);
    progress("complete", counts);
    return 0;
}
