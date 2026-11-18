// DXMT v0.80, commit 589adb780354b461645b29999cefaf533594ee99.
// cache_18 maps a 40-byte (shader SHA1, variant SHA1) key to a Metal library.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <signal.h>
#include <sqlite3.h>
#include <stdatomic.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>

// Only the generated Metal pair is preserved, capped at 512 MiB per snapshot.
static const unsigned long long native_pair_limit = 512ULL * 1024 * 1024;

static _Atomic sig_atomic_t cancelled;
static void cancel_work(int signal_number) { (void)signal_number; cancelled = 1; }

static void fail(NSString *message) { @throw [NSError errorWithDomain:@"Arclume.MetalShaders" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static void emit(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}
// Only report work the helper has actually finished. A blocked operation must
// stop producing events so the parent can detect it.
static void activity(NSString *phase, NSUInteger processed, NSUInteger total, NSUInteger failed, BOOL final) {
    static uint64_t last;
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (!final && now - last < 250 * NSEC_PER_MSEC) return;
    last = now;
    emit(@{@"event":@"progress", @"progress":@{@"phase":phase, @"processed":@(processed),
        @"total":@(total), @"failed":@(failed)}});
}

static NSString *hex_bytes(const unsigned char *bytes, NSUInteger length) {
    static const char alphabet[] = "0123456789abcdef";
    char encoded[80];
    for (NSUInteger i = 0; i < length; ++i) {
        encoded[2*i] = alphabet[bytes[i] >> 4];
        encoded[2*i+1] = alphabet[bytes[i] & 15];
    }
    return [[NSString alloc] initWithBytes:encoded length:2*length encoding:NSASCIIStringEncoding];
}
static NSString *digest(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    return hex_bytes(bytes,sizeof(bytes));
}
static NSDictionary *native_pair(NSString *directory) {
    NSMutableDictionary *sizes = [NSMutableDictionary new];
    unsigned long long total = 0;
    NSMutableArray *candidates = [NSMutableArray arrayWithObject:@""];
    NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
    if (children.count > 64) return nil;
    NSRegularExpression *driverName = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{1,20}_[0-9]{1,20}$" options:0 error:nil];
    for (NSString *child in children) {
        struct stat info;
        if ([driverName numberOfMatchesInString:child options:0 range:NSMakeRange(0,child.length)] == 1
            && !lstat([[directory stringByAppendingPathComponent:child] fileSystemRepresentation],&info)
            && S_ISDIR(info.st_mode)) [candidates addObject:child];
    }
    for (NSString *candidate in candidates) {
        NSMutableDictionary *pair = [NSMutableDictionary new];
        for (NSString *name in @[@"functions.data", @"functions.list"]) {
            NSString *relative = [candidate stringByAppendingPathComponent:name];
            struct stat info;
            if (lstat([[directory stringByAppendingPathComponent:relative] fileSystemRepresentation], &info)
                || !S_ISREG(info.st_mode) || info.st_size <= 0) { [pair removeAllObjects]; break; }
            pair[relative] = @{ @"size":@(info.st_size), @"seconds":@(info.st_mtimespec.tv_sec), @"nanoseconds":@(info.st_mtimespec.tv_nsec) };
        }
        for (NSString *name in pair) {
            total += [pair[name][@"size"] unsignedLongLongValue];
            if (total > native_pair_limit) return nil;
            sizes[name] = pair[name];
        }
    }
    return sizes.count ? sizes : nil;
}
static NSString *copy_native_file(NSString *source, NSString *destination) {
    int input = open(source.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    struct stat before, after;
    if (input < 0 || fstat(input,&before) || !S_ISREG(before.st_mode)
        || before.st_size <= 0 || (unsigned long long)before.st_size > native_pair_limit) {
        if (input >= 0) close(input);
        fail(@"Metal 原生缓存当前不可读取。");
    }
    [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    int output = open(destination.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (output < 0) { close(input); fail(@"无法保存 Metal 原生缓存。"); }
    CC_SHA256_CTX hash;
    CC_SHA256_Init(&hash);
    unsigned char buffer[64 * 1024];
    unsigned long long copied = 0;
    BOOL success = YES;
    ssize_t length;
    while ((length = read(input,buffer,sizeof(buffer))) > 0) {
        if (cancelled || (copied += (unsigned long long)length) > native_pair_limit) { success = NO; break; }
        CC_SHA256_Update(&hash,buffer,(CC_LONG)length);
        if (copied % (4 * 1024 * 1024) == 0) activity(@"backup", copied, before.st_size, 0, NO);
        ssize_t offset = 0;
        while (offset < length) {
            ssize_t count = write(output,buffer+offset,(size_t)(length-offset));
            if (count <= 0) { success = NO; break; }
            offset += count;
        }
        if (!success) break;
    }
    if (length < 0 || fstat(input,&after) || copied != (unsigned long long)before.st_size
        || before.st_size != after.st_size || before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec
        || before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec || fsync(output)) success = NO;
    close(input); close(output);
    if (!success) { unlink(destination.fileSystemRepresentation); fail(@"Metal 缓存仍在变化或保存已取消，请退出游戏后重试。"); }
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(bytes,&hash);
    return hex_bytes(bytes,sizeof(bytes));
}
static NSString *native_backup_path(NSString *cache, NSString *context) {
    NSString *key = digest([context dataUsingEncoding:NSUTF8StringEncoding]);
    return [[cache stringByAppendingPathComponent:@"NativeMetal"] stringByAppendingPathComponent:key];
}
static NSData *bounded_data(NSString *path, unsigned long long limit) {
    struct stat info;
    if (lstat(path.fileSystemRepresentation,&info) || !S_ISREG(info.st_mode)
        || info.st_size < 0 || (unsigned long long)info.st_size > limit) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    return data.length <= limit ? data : nil;
}
static NSDictionary *prepared_records(NSData *data, NSString *context) {
    NSDictionary *receipt = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![receipt isKindOfClass:NSDictionary.class] || ![receipt[@"context"] isEqual:context]
        || ![receipt[@"prepared"] isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *records = [NSMutableDictionary new];
    for (id key in receipt[@"prepared"]) {
        id value = receipt[@"prepared"][key];
        if ([key isKindOfClass:NSString.class] && [key length] <= 512
            && [value isKindOfClass:NSNumber.class] && [value longLongValue] >= 0) records[key] = value;
    }
    return records;
}
static NSDictionary *native_backup(NSString *backup, NSString *context, BOOL includeCoverage) {
    NSData *data = bounded_data([backup stringByAppendingPathComponent:@"manifest.json"],64 * 1024);
    NSDictionary *manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"context"] isEqual:context]) return nil;
    NSDictionary *sizes = native_pair(backup);
    if (!sizes || ![manifest[@"files"] isKindOfClass:NSDictionary.class] || [manifest[@"files"] count] != sizes.count) return nil;
    for (NSString *name in sizes) {
        if (![manifest[@"files"][name] isKindOfClass:NSDictionary.class]
            || ![sizes[name][@"size"] isEqual:manifest[@"files"][name][@"size"]]
            || ![manifest[@"files"][name][@"sha256"] isKindOfClass:NSString.class]) return nil;
    }
    if (!includeCoverage) return manifest;
    // Coverage is captured only after the compiler has exited and flushed this pair.
    NSData *coverage = bounded_data([backup stringByAppendingPathComponent:@"prepared.json"],128ULL * 1024 * 1024);
    NSDictionary *records = coverage && [manifest[@"receiptSHA256"] isEqual:digest(coverage)]
        ? prepared_records(coverage,context) : @{};
    NSMutableDictionary *result = [manifest mutableCopy];
    result[@"prepared"] = records;
    return result;
}
static void preserve_native(NSString *native, NSString *backup, NSString *context, NSData *coverage) {
    NSDictionary *sizes = native_pair(native);
    if (!sizes) return;
    NSString *receiptHash = digest(coverage);
    NSDictionary *existing = native_backup(backup,context,NO);
    if ([existing[@"source"] isEqual:sizes] && [existing[@"receiptSHA256"] isEqual:receiptHash]) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *parent = backup.stringByDeletingLastPathComponent;
    NSString *staging = [parent stringByAppendingPathComponent:[@".staging-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil]) fail(@"无法创建应用内 Metal 缓存目录。");
    @try {
        NSMutableDictionary *files = [NSMutableDictionary new];
        for (NSString *name in sizes) {
            NSString *hash = copy_native_file([native stringByAppendingPathComponent:name],[staging stringByAppendingPathComponent:name]);
            files[name] = @{ @"size":sizes[name][@"size"], @"sha256":hash };
        }
        if (![sizes isEqual:native_pair(native)]) fail(@"Metal 缓存仍在变化，请退出游戏后重试。");
        if (![coverage writeToFile:[staging stringByAppendingPathComponent:@"prepared.json"] options:NSDataWritingAtomic error:nil]) fail(@"无法保存原生缓存完成记录。");
        NSData *manifest = [NSJSONSerialization dataWithJSONObject:@{@"context":context,@"source":sizes,@"files":files,@"receiptSHA256":receiptHash} options:0 error:nil];
        if (![manifest writeToFile:[staging stringByAppendingPathComponent:@"manifest.json"] options:NSDataWritingAtomic error:nil]) fail(@"无法保存 Metal 缓存信息。");
        struct stat info;
        if (lstat(backup.fileSystemRepresentation,&info) == 0) {
            if (!S_ISDIR(info.st_mode) || renamex_np(staging.fileSystemRepresentation,backup.fileSystemRepresentation,RENAME_SWAP)) fail(@"无法更新应用内 Metal 缓存。");
        } else if (errno != ENOENT || rename(staging.fileSystemRepresentation,backup.fileSystemRepresentation)) fail(@"无法保存应用内 Metal 缓存。");
    } @finally { [fm removeItemAtPath:staging error:nil]; }
}
static void restore_native(NSString *native, NSString *backup, NSString *context) {
    NSDictionary *manifest = native_backup(backup,context,NO);
    if (!manifest) return;
    // Existing or incomplete live caches belong to DXMT and are never overwritten.
    struct stat info;
    NSArray *names = [manifest[@"files"] allKeys];
    for (NSString *name in names) {
        if (lstat([[native stringByAppendingPathComponent:name] fileSystemRepresentation],&info) == 0 || errno != ENOENT) return;
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:native withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *temporary = [NSMutableArray new], *published = [NSMutableArray new];
    BOOL success = NO;
    @try {
        for (NSString *name in names) {
            NSString *temp = [native stringByAppendingPathComponent:[@".arclume-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            [temporary addObject:temp];
            NSString *hash = copy_native_file([backup stringByAppendingPathComponent:name],temp);
            if (![hash isEqual:manifest[@"files"][name][@"sha256"]]) fail(@"应用内 Metal 缓存校验失败，请重新优化。");
        }
        NSUInteger index = 0;
        for (NSString *name in names) {
            NSString *destination = [native stringByAppendingPathComponent:name];
            [fm createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            if (link([temporary[index++] fileSystemRepresentation],destination.fileSystemRepresentation)) fail(@"Metal 缓存已被其他程序打开，请退出游戏后重试。");
            [published addObject:destination];
        }
        success = YES;
    } @finally {
        for (NSString *path in temporary) unlink(path.fileSystemRepresentation);
        if (!success) for (NSString *path in published) unlink(path.fileSystemRepresentation);
    }
}
static sqlite3 *open_db(NSString *path, BOOL write) {
    sqlite3 *db = NULL;
    int flags = write ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY;
    if (sqlite3_open_v2(path.fileSystemRepresentation, &db, flags | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        sqlite3_close(db);
        fail(@"无法打开 DXMT 着色器数据库。");
    }
    sqlite3_busy_timeout(db, 5000);
    return db;
}
static NSArray<NSString *> *files(NSString *source, BOOL external) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL directory = NO;
    if (![fm fileExistsAtPath:source isDirectory:&directory]) return @[];
    if (!directory) return @[source];
    NSMutableArray *paths = [NSMutableArray new];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:source]
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
    NSUInteger visited = 0;
    for (NSURL *url in enumerator) {
        if (cancelled) break;
        if (++visited > 8192) fail(@"所选缓存目录的文件过多，请选择具体游戏的缓存目录。");
        if ((!external && enumerator.level > 1) || enumerator.level > 4) { [enumerator skipDescendants]; continue; }
        NSNumber *regular, *link;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];
        if (link.boolValue) { [enumerator skipDescendants]; continue; }
        if (regular.boolValue && [@[@"db", @"metallib"] containsObject:url.pathExtension.lowercaseString]) [paths addObject:url.path];
    }
    return [paths sortedArrayUsingSelector:@selector(compare:)];
}

static NSData *read_library(NSString *path) {
    NSData *data = bounded_data(path, 64 * 1024 * 1024);
    if (data.length < 4 || memcmp(data.bytes,"MTLB",4)) fail(@"所选文件不是有效的 Metal 着色器库。");
    return data;
}

static void scan_file(NSString *path, NSMutableDictionary *entries, BOOL external) {
    NSString *name = path.lastPathComponent;
    if ([path.pathExtension.lowercaseString isEqualToString:@"metallib"]) {
        NSString *identity = [@"library:" stringByAppendingString:digest(read_library(path))];
        if (!entries[identity]) entries[identity] = @{@"file":path};
        activity(@"scan", entries.count, 0, 0, NO);
        return;
    }
    if (![path.pathExtension.lowercaseString isEqualToString:@"db"]) return;
    if (!external && ![name hasPrefix:@"shaders_"]) return;

    sqlite3 *db = open_db(path, NO);
    sqlite3_stmt *stmt = NULL;
    NSString *database = [name hasPrefix:@"shaders_"] ? name : @"shaders_320.db";
    @try {
        // The key index covers this scan, even when the libraries span many GB.
        if (sqlite3_prepare_v2(db, "SELECT key,rowid FROM cache_18 WHERE typeof(key)='blob' AND length(key)=40 ORDER BY key",
                               -1, &stmt, NULL) != SQLITE_OK) {
            if (external) fail(@"所选数据库缺少 DXMT 0.80 的 cache_18 着色器表。");
            return;
        }
        int step;
        NSUInteger visited = 0;
        while (!cancelled && (step = sqlite3_step(stmt)) == SQLITE_ROW) {
            @autoreleasepool {
                NSData *key = [NSData dataWithBytes:sqlite3_column_blob(stmt,0) length:40];
                NSString *record = [NSString stringWithFormat:@"%@:%@", database, hex_bytes(key.bytes,key.length)];
                if (!entries[record]) entries[record] = @{@"db":path, @"database":database, @"key":key, @"row":@(sqlite3_column_int64(stmt,1))};
            }
            if (++visited % 256 == 0) activity(@"scan", entries.count, 0, 0, NO);
        }
        if (!cancelled && step != SQLITE_DONE) fail(@"读取 DXMT 着色器数据库失败。");
    } @finally { sqlite3_finalize(stmt); sqlite3_close(db); }
}

@interface ShaderDatabase : NSObject {
    sqlite3 *_db;
    sqlite3_stmt *_statement;
    sqlite3_stmt *_contains;
}
- (instancetype)initWithPath:(NSString *)path writing:(BOOL)writing;
- (NSData *)readKey:(NSData *)key;
- (BOOL)containsKey:(NSData *)key;
- (void)insertKey:(NSData *)key library:(NSData *)library;
@end

@implementation ShaderDatabase
- (instancetype)initWithPath:(NSString *)path writing:(BOOL)writing {
    if ((self = [super init])) {
        _db = open_db(path, writing);
        if (writing && sqlite3_exec(_db, "PRAGMA journal_mode=WAL;CREATE TABLE IF NOT EXISTS cache_18(key BLOB PRIMARY KEY,value BLOB NOT NULL)",
                                    NULL,NULL,NULL) != SQLITE_OK) fail(@"无法准备应用内 DXMT 缓存。");
        const char *sql = writing ? "INSERT OR IGNORE INTO cache_18(key,value) VALUES(?,?)" : "SELECT value FROM cache_18 WHERE key=?";
        if (sqlite3_prepare_v2(_db, sql, -1, &_statement, NULL) != SQLITE_OK
            || (writing && sqlite3_prepare_v2(_db, "SELECT 1 FROM cache_18 WHERE key=?", -1, &_contains, NULL) != SQLITE_OK))
            fail(@"无法打开 DXMT 着色器表。");
    }
    return self;
}
- (void)dealloc { sqlite3_finalize(_contains); sqlite3_finalize(_statement); sqlite3_close(_db); }
- (BOOL)containsKey:(NSData *)key {
    sqlite3_bind_blob(_contains,1,key.bytes,(int)key.length,SQLITE_STATIC);
    int step = sqlite3_step(_contains);
    sqlite3_reset(_contains);
    sqlite3_clear_bindings(_contains);
    if (step != SQLITE_ROW && step != SQLITE_DONE) fail(@"无法查询 DXMT 着色器。");
    return step == SQLITE_ROW;
}
- (NSData *)readKey:(NSData *)key {
    sqlite3_bind_blob(_statement,1,key.bytes,(int)key.length,SQLITE_STATIC);
    @try {
        if (sqlite3_step(_statement) != SQLITE_ROW) fail(@"着色器缓存已变化，请重新检查。");
        int size = sqlite3_column_bytes(_statement,0);
        const void *value = sqlite3_column_blob(_statement,0);
        if (size < 4 || size > 64 * 1024 * 1024 || !value || memcmp(value,"MTLB",4))
            fail(@"DXMT 缓存包含无法识别的着色器库。");
        return [NSData dataWithBytes:value length:size];
    } @finally { sqlite3_reset(_statement); sqlite3_clear_bindings(_statement); }
}
- (void)insertKey:(NSData *)key library:(NSData *)library {
    sqlite3_bind_blob(_statement,1,key.bytes,(int)key.length,SQLITE_STATIC);
    sqlite3_bind_blob(_statement,2,library.bytes,(int)library.length,SQLITE_STATIC);
    int step = sqlite3_step(_statement);
    sqlite3_reset(_statement);
    sqlite3_clear_bindings(_statement);
    if (step != SQLITE_DONE) fail(@"无法保存 DXMT 着色器。");
}
@end

static NSData *entry_data(NSDictionary *entry, NSMutableDictionary<NSString *,ShaderDatabase *> *readers) {
    if (entry[@"file"]) return read_library(entry[@"file"]);
    NSString *path = entry[@"db"];
    ShaderDatabase *reader = readers[path];
    if (!reader) readers[path] = reader = [[ShaderDatabase alloc] initWithPath:path writing:NO];
    return [reader readKey:entry[@"key"]];
}

static void import_entries(NSDictionary *entries, NSString *directory) {
    NSMutableDictionary<NSString *,ShaderDatabase *> *readers = [NSMutableDictionary new], *writers = [NSMutableDictionary new];
    NSUInteger processed = 0;
    for (NSDictionary *entry in entries.objectEnumerator) {
        if (cancelled) break;
        @autoreleasepool {
            NSString *source = entry[@"db"];
            if (!source || [source.stringByDeletingLastPathComponent isEqualToString:directory]) continue;
            NSString *target = [directory stringByAppendingPathComponent:entry[@"database"]];
            if ([target.stringByResolvingSymlinksInPath isEqualToString:source.stringByResolvingSymlinksInPath]) continue;
            ShaderDatabase *writer = writers[target];
            if (!writer) writers[target] = writer = [[ShaderDatabase alloc] initWithPath:target writing:YES];
            if (![writer containsKey:entry[@"key"]]) [writer insertKey:entry[@"key"] library:entry_data(entry,readers)];
        }
        activity(@"import", ++processed, 0, 0, NO);
    }
}

static NSString *journal_path(NSString *cache, NSString *session) {
    NSUUID *identifier = session ? [[NSUUID alloc] initWithUUIDString:session] : nil;
    if (!identifier) fail(@"缺少有效的着色器任务编号。");
    return [cache stringByAppendingPathComponent:[NSString stringWithFormat:@".prepared-%@.jsonl", identifier.UUIDString]];
}

static void append_checkpoint(int fd, NSString *identity, NSNumber *kernels) {
    NSData *record = [NSJSONSerialization dataWithJSONObject:@[identity,kernels] options:0 error:nil];
    if (!record) fail(@"无法编码着色器准备记录。");
    NSMutableData *line = [record mutableCopy];
    [line appendBytes:"\n" length:1];
    NSUInteger offset = 0;
    while (offset < line.length) {
        ssize_t count = write(fd, (const char *)line.bytes + offset, line.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) fail(@"无法保存着色器准备记录。");
        offset += (NSUInteger)count;
    }
}

static BOOL merge_checkpoints(NSString *path, NSMutableDictionary *prepared) {
    int fd = open(path.fileSystemRepresentation,O_RDONLY | O_NOFOLLOW);
    if (fd < 0 && errno == ENOENT) return NO;
    FILE *file = fd >= 0 ? fdopen(fd,"r") : NULL;
    if (!file) {
        if (fd >= 0) close(fd);
        fail(@"无法读取本次着色器准备记录。");
    }
    char line[1024];
    BOOL changed = NO;
    NSUInteger processed = 0;
    @try {
        while (!cancelled && fgets(line,sizeof(line),file)) {
            @autoreleasepool {
                size_t length = strlen(line);
                if (length == 0 || line[length-1] != '\n') fail(@"本次着色器准备记录不完整。");
                NSData *data = [NSData dataWithBytes:line length:length];
                NSArray *record = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (![record isKindOfClass:NSArray.class] || record.count != 2 || ![record[0] isKindOfClass:NSString.class]
                    || ![record[1] isKindOfClass:NSNumber.class] || [record[1] longLongValue] < 0)
                    fail(@"本次着色器准备记录无效。");
                prepared[record[0]] = record[1];
                changed = YES;
            }
            if (++processed % 256 == 0) activity(@"backup",processed,0,0,NO);
        }
        if (ferror(file)) fail(@"无法读取本次着色器准备记录。");
    } @finally { fclose(file); }
    return changed;
}

static NSNumber *prepare_library(id<MTLDevice> device, NSData *blob) {
    NSError *error = nil;
    dispatch_data_t data = dispatch_data_create(blob.bytes,blob.length,nil,DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    id<MTLLibrary> library = [device newLibraryWithData:data error:&error];
    if (!library || library.functionNames.count == 0) return nil;
    NSUInteger kernels = 0;
    for (NSString *name in library.functionNames) {
        if (cancelled) return nil;
        id<MTLFunction> function = [library newFunctionWithName:name];
        if (!function) return nil;
        if (function.functionType != MTLFunctionTypeKernel) continue;
        // DXMT pins slots 29/30 immutable. Both legal threadgroup variants may be used.
        for (NSNumber *multiple in @[@NO,@YES]) {
            MTLComputePipelineDescriptor *desc = [MTLComputePipelineDescriptor new];
            desc.computeFunction = function;
            desc.buffers[29].mutability = MTLMutabilityImmutable;
            desc.buffers[30].mutability = MTLMutabilityImmutable;
            desc.threadGroupSizeIsMultipleOfThreadExecutionWidth = multiple.boolValue;
            id<MTLComputePipelineState> state = [device newComputePipelineStateWithDescriptor:desc options:0 reflection:nil error:&error];
            if (!state) return nil;
        }
        kernels++;
    }
    return @(kernels);
}

static NSArray *prepare_batch(id<MTLDevice> device, NSArray<NSDictionary *> *jobs) {
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:jobs.count];
    for (NSUInteger i = 0; i < jobs.count; i++) [results addObject:NSNull.null];
    dispatch_apply(jobs.count, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t i) {
        @autoreleasepool {
            if (cancelled) return;
            NSNumber *result = prepare_library(device, jobs[i][@"data"]);
            if (result) @synchronized (results) { results[i] = result; }
        }
    });
    return results;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        signal(SIGTERM,cancel_work);
        signal(SIGINT,cancel_work);
        @try {
            if (argc < 2) fail(@"缺少着色器准备操作。");
            NSString *mode = @(argv[1]);
            NSMutableDictionary<NSString *,NSString *> *args = [NSMutableDictionary new];
            for (int i=2; i+1<argc; i+=2) args[@(argv[i])] = @(argv[i+1]);
            NSString *cache = args[@"--cache-dir"], *legacy = args[@"--legacy-dir"], *native = args[@"--native-cache-dir"];
            if (!cache.isAbsolutePath || !legacy.isAbsolutePath || !native.isAbsolutePath) fail(@"缓存路径不完整。");
            BOOL optimize = [mode isEqualToString:@"optimize"];
            BOOL preserve = [mode isEqualToString:@"preserve"];
            BOOL importing = [mode isEqualToString:@"import"];
            BOOL writeMode = optimize || preserve || importing;
            if (!writeMode && ![mode isEqualToString:@"inspect"]) fail(@"未知着色器准备操作。");
            int lock = -1;
            if (writeMode) {
                [NSFileManager.defaultManager createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
                lock = open([[cache stringByAppendingPathComponent:@".preparation-lock"] fileSystemRepresentation],O_CREAT | O_RDWR,0600);
                if (lock < 0 || flock(lock,LOCK_EX | LOCK_NB)) fail(@"此游戏的着色器准备已在进行。");
            }
            NSString *journal = optimize || preserve ? journal_path(cache,args[@"--session"]) : nil;
            NSInteger workers = args[@"--workers"] ? [args[@"--workers"] integerValue] : 1;
            if (workers < 1 || workers > 16) fail(@"着色器处理线程数超出范围。");
            if (optimize) {
                void (*setPath)(NSString *) = dlsym(RTLD_DEFAULT,"MTLSetShaderCachePath");
                NSString *(*getPath)(void) = dlsym(RTLD_DEFAULT,"MTLGetShaderCachePath");
                if (!setPath || !getPath) fail(@"当前系统未提供与 DXMT 共享的 Metal 缓存接口。");
                [NSFileManager.defaultManager createDirectoryAtPath:native withIntermediateDirectories:YES attributes:nil error:nil];
                setPath(native);
                if (![[getPath() stringByResolvingSymlinksInPath] isEqual:native.stringByResolvingSymlinksInPath])
                    fail(@"无法启用与 DXMT 共享的 Metal 缓存。");
            }
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            if (!device) fail(@"此 Mac 无法使用 Metal 着色器准备。");
            NSString *context = [NSString stringWithFormat:@"DXMT0.80/cache18/rev1/%llu/%@",device.registryID,NSProcessInfo.processInfo.operatingSystemVersionString];
            NSString *backup = native_backup_path(cache,context);
            NSString *receiptPath = [cache stringByAppendingPathComponent:@"prepared.json"];
            BOOL liveNativeExists = native_pair(native) != nil;
            NSData *savedData = importing && liveNativeExists ? nil : bounded_data(receiptPath,128ULL * 1024 * 1024);
            NSDictionary *saved = prepared_records(savedData,context);
            NSMutableDictionary *prepared = [NSMutableDictionary new];
            if (liveNativeExists) {
                [prepared addEntriesFromDictionary:saved];
            } else if (saved.count) {
                NSDictionary *covered = native_backup(backup,context,YES)[@"prepared"];
                for (NSString *identity in saved) {
                    if ([saved[identity] isEqual:covered[identity]]) prepared[identity] = saved[identity];
                }
            }
            if (importing && !liveNativeExists) restore_native(native,backup,context);
            if (importing && native_pair(native) && !liveNativeExists && prepared.count != saved.count) {
                // Restoring an older pair must not reactivate newer, uncovered marks.
                NSData *receipt = [NSJSONSerialization dataWithJSONObject:@{@"context":context,@"prepared":prepared}
                    options:NSJSONWritingSortedKeys error:nil];
                if (![receipt writeToFile:receiptPath options:NSDataWritingAtomic error:nil]) fail(@"无法核对已恢复的原生缓存完成记录。");
            }

            NSUInteger observed = 0;
            __block NSUInteger done = 0, compute = 0, failures = 0, processed = 0;
            if (preserve) {
                BOOL changed = merge_checkpoints(journal,prepared);
                if (!cancelled && changed && !liveNativeExists)
                    fail(@"Metal 未生成可保存的原生缓存。已保留着色器库和任务记录。");
                if (!cancelled && liveNativeExists && (changed || saved.count)) {
                    NSData *receipt = savedData;
                    if (changed) {
                        receipt = [NSJSONSerialization dataWithJSONObject:@{@"context":context,@"prepared":prepared}
                            options:NSJSONWritingSortedKeys error:nil];
                        if (!receipt || receipt.length > 128ULL * 1024 * 1024
                            || ![receipt writeToFile:receiptPath options:NSDataWritingAtomic error:nil])
                            fail(@"无法保存着色器完成记录。");
                    }
                    preserve_native(native,backup,context,receipt);
                }
                if (!cancelled) unlink(journal.fileSystemRepresentation);
            } else {
                NSMutableDictionary *entries = [NSMutableDictionary new];
                NSArray *legacyFiles = files(legacy,NO);
                NSString *external = args[@"--external-source"];
                NSArray *externalFiles = external ? files(external,YES) : @[];
                if (external && externalFiles.count == 0) fail(@"外置目录没有可读取的 DXMT 数据库或 Metal 库。");
                if (!importing) for (NSString *path in files(cache,NO)) scan_file(path,entries,NO);
                for (NSString *path in legacyFiles) scan_file(path,entries,NO);
                for (NSString *path in externalFiles) scan_file(path,entries,YES);
                observed = entries.count;
                if (importing) {
                    import_entries(entries,cache);
                } else if (!cancelled && (optimize || prepared.count)) {
                    // Retain SHA-256 matching with existing receipts. DXMT may replace an
                    // existing key, so a key match alone cannot mark the library as prepared.
                    NSMutableSet *receiptKeys = [NSMutableSet new];
                    if (!optimize) for (NSString *identity in prepared) {
                        if (identity.length > 65) [receiptKeys addObject:[identity substringToIndex:identity.length-65]];
                    }
                    NSMutableDictionary<NSString *,ShaderDatabase *> *readers = [NSMutableDictionary new];
                    NSArray *ordered = [entries keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                        NSString *left = a[@"db"] ?: a[@"file"], *right = b[@"db"] ?: b[@"file"];
                        NSComparisonResult source = left == right ? NSOrderedSame : [left compare:right];
                        return source == NSOrderedSame && a[@"row"] ? [a[@"row"] compare:b[@"row"]] : source;
                    }];
                    int checkpoint = optimize ? open(journal.fileSystemRepresentation,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,0600) : -1;
                    if (optimize && checkpoint < 0) fail(@"无法创建本次着色器准备记录。");
                    __block NSUInteger unsynced = 0, queuedBytes = 0;
                    __block uint64_t lastSync = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
                    NSMutableArray<NSDictionary *> *jobs = [NSMutableArray arrayWithCapacity:(NSUInteger)workers];
                    void (^flushJobs)(void) = ^{
                        if (!jobs.count || cancelled) return;
                        NSArray *results = prepare_batch(device,jobs);
                        for (NSUInteger index = 0; index < jobs.count; index++) {
                            id complete = results[index];
                            if (complete != NSNull.null) {
                                append_checkpoint(checkpoint,jobs[index][@"identity"],complete);
                                done++;
                                compute += [complete unsignedIntegerValue];
                                uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
                                if (++unsynced >= 128 || now - lastSync >= NSEC_PER_SEC) {
                                    if (fsync(checkpoint)) fail(@"无法保存着色器准备记录。");
                                    unsynced = 0;
                                    lastSync = now;
                                }
                            } else if (cancelled) {
                                continue;
                            } else {
                                failures++;
                            }
                            activity(@"optimize", ++processed, observed, failures, NO);
                        }
                        [jobs removeAllObjects];
                        queuedBytes = 0;
                    };
                    @try {
                        for (NSString *key in ordered) {
                            if (cancelled) break;
                            @autoreleasepool {
                                NSDictionary *entry = entries[key];
                                NSString *identity = key;
                                NSData *blob = nil;
                                if (entry[@"db"] && (optimize || [receiptKeys containsObject:key])) {
                                    blob = entry_data(entry,readers);
                                    identity = [key stringByAppendingFormat:@":%@",digest(blob)];
                                }
                                NSNumber *complete = prepared[identity];
                                if (optimize && !complete) {
                                    if (!blob) {
                                        blob = entry_data(entry,readers);
                                        if (![[@"library:" stringByAppendingString:digest(blob)] isEqual:key])
                                            fail(@"着色器缓存已变化，请重新检查。");
                                    }
                                    // Bound both the number of Metal calls and the queued library bytes.
                                    if (queuedBytes + blob.length > 128 * 1024 * 1024) flushJobs();
                                    [jobs addObject:@{@"identity":identity, @"data":blob}];
                                    queuedBytes += blob.length;
                                    if (jobs.count >= (NSUInteger)workers) flushJobs();
                                } else {
                                    if (complete) { done++; compute += complete.unsignedIntegerValue; }
                                    activity(optimize ? @"optimize" : @"verify", ++processed, observed, failures, NO);
                                }
                            }
                        }
                        flushJobs();
                    } @finally {
                        if (checkpoint >= 0) {
                            int flush = unsynced ? fsync(checkpoint) : 0;
                            int closed = close(checkpoint);
                            if (flush || closed) fail(@"无法保存着色器准备记录。");
                        }
                    }
                    if (optimize) activity(@"optimize", processed, observed, failures, YES);
                }
            }
            if (lock >= 0) { flock(lock,LOCK_UN); close(lock); }
            if (cancelled) return 130;
            emit(@{@"event":@"snapshot",@"snapshot":@{@"observed":@(observed),@"prepared":@(done),
                @"pending":@(observed-done),@"computePipelines":@(compute),@"failed":@(failures)}});
            return 0;
        } @catch (NSError *error) {
            emit(@{@"event":@"error",@"message":error.localizedDescription});
            return 1;
        }
    }
}
