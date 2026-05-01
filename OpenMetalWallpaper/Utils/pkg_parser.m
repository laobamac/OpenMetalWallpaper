#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <unistd.h>

@interface PkgEntry : NSObject
@property (nonatomic, strong) NSString *path;
@property (nonatomic, assign) int32_t offset;
@property (nonatomic, assign) int32_t length;
@end

@implementation PkgEntry
@end

@interface PkgReader : NSObject
@property (nonatomic, strong) NSString *filepath;
@property (nonatomic, strong) NSString *magic;
@property (nonatomic, strong) NSMutableArray<PkgEntry *> *entries;
@property (nonatomic, assign) unsigned long long dataStartOffset;
- (instancetype)initWithFilepath:(NSString *)filepath;
- (BOOL)extractEntry:(PkgEntry *)entry toOutputDir:(NSString *)outputDir;
- (NSDictionary *)dumpInfo;
@end

@implementation PkgReader

- (instancetype)initWithFilepath:(NSString *)filepath {
    self = [super init];
    if (self) {
        _filepath = filepath;
        _entries = [NSMutableArray array];
        if (![self parse]) {
            return nil;
        }
    }
    return self;
}

- (NSString *)readStringFromFileHandle:(NSFileHandle *)handle {
    NSError *error = nil;
    NSData *lengthData = [handle readDataUpToLength:4 error:&error];
    if (!lengthData || lengthData.length < 4) return nil;
    int32_t length = 0;
    [lengthData getBytes:&length length:sizeof(length)];
    length = CFSwapInt32LittleToHost(length);
    if (length < 0 || length > 4096) return nil;
    if (length == 0) return @"";
    NSData *strData = [handle readDataUpToLength:length error:&error];
    if (!strData) return nil;
    NSString *str = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
    if (!str) {
        str = [[NSString alloc] initWithData:strData encoding:NSISOLatin1StringEncoding];
    }
    return str;
}

- (BOOL)parse {
    NSError *error = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:self.filepath] error:&error];
    if (!handle) return NO;
    
    self.magic = [self readStringFromFileHandle:handle];
    
    NSData *countData = [handle readDataUpToLength:4 error:&error];
    if (!countData || countData.length < 4) {
        [handle closeAndReturnError:nil];
        return NO;
    }
    int32_t entryCount = 0;
    [countData getBytes:&entryCount length:4];
    entryCount = CFSwapInt32LittleToHost(entryCount);
    
    for (int32_t i = 0; i < entryCount; i++) {
        NSString *path = [self readStringFromFileHandle:handle];
        NSData *offsetData = [handle readDataUpToLength:4 error:&error];
        int32_t offset = 0;
        [offsetData getBytes:&offset length:4];
        offset = CFSwapInt32LittleToHost(offset);
        
        NSData *lenData = [handle readDataUpToLength:4 error:&error];
        int32_t length = 0;
        [lenData getBytes:&length length:4];
        length = CFSwapInt32LittleToHost(length);
        
        PkgEntry *entry = [[PkgEntry alloc] init];
        entry.path = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        entry.offset = offset;
        entry.length = length;
        [self.entries addObject:entry];
    }
    
    unsigned long long currentOffset = 0;
    [handle getOffset:&currentOffset error:nil];
    self.dataStartOffset = currentOffset;
    [handle closeAndReturnError:nil];
    return YES;
}

- (BOOL)extractEntry:(PkgEntry *)entry toOutputDir:(NSString *)outputDir {
    NSString *fullPath = [outputDir stringByAppendingPathComponent:entry.path];
    NSString *parentDir = [fullPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSError *error = nil;
    NSFileHandle *src = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:self.filepath] error:&error];
    if (!src) return NO;
    [src seekToOffset:(self.dataStartOffset + entry.offset) error:nil];
    NSData *data = [src readDataUpToLength:entry.length error:nil];
    [src closeAndReturnError:nil];
    
    return [fm createFileAtPath:fullPath contents:data attributes:nil];
}

- (NSDictionary *)dumpInfo {
    NSMutableArray *files = [NSMutableArray array];
    for (PkgEntry *e in self.entries) {
        [files addObject:@{@"path": e.path, @"offset": @(e.offset), @"length": @(e.length)}];
    }
    return @{@"magic": self.magic ?: @"", @"entry_count": @(self.entries.count), @"files": files};
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL isDebug = NO;
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "-d") == 0) {
                isDebug = YES;
                break;
            }
        }
        
        if (!isDebug) {
            pid_t ppid = getppid();
            NSRunningApplication *pApp = [NSRunningApplication runningApplicationWithProcessIdentifier:ppid];
            NSString *pID = pApp.bundleIdentifier;
            
            char t[] = {0x63, 0x6e, 0x2e, 0x6c, 0x61, 0x6f, 0x62, 0x61, 0x6d, 0x61, 0x63, 0x4f, 0x70, 0x65, 0x6e, 0x4d, 0x65, 0x74, 0x61, 0x6c, 0x57, 0x61, 0x6c, 0x6c, 0x70, 0x61, 0x70, 0x65, 0x72, 0x00};
            NSString *eID = [NSString stringWithUTF8String:t];
            
            if (!pID || ![pID isEqualToString:eID]) {
                return 0;
            }
        }

        if (argc < 2) {
            if (isDebug) printf("用法: pkg_parser <input_path> [-i] [-o <output_dir>] [-d]\n");
            return 1;
        }
        
        BOOL isInfo = NO;
        NSString *outputPath = nil;
        NSString *inputPath = nil;
        
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"-d"]) {
                continue;
            } else if ([arg isEqualToString:@"-i"] || [arg isEqualToString:@"--info"]) {
                isInfo = YES;
            } else if ([arg isEqualToString:@"-o"] || [arg isEqualToString:@"--output"]) {
                if (i + 1 < argc) {
                    outputPath = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if (![arg hasPrefix:@"-"]) {
                inputPath = arg;
            }
        }
        
        if (!inputPath) {
            if (isDebug) printf("错误: 未提供输入路径\n");
            return 1;
        }
        
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:inputPath isDirectory:&isDir]) {
            if (isDebug) printf("错误: 输入路径不存在\n");
            return 1;
        }
        
        NSString *pkgFile = nil;
        if (!isDir) {
            if ([[[inputPath pathExtension] lowercaseString] isEqualToString:@"pkg"]) {
                pkgFile = inputPath;
            } else {
                if (isDebug) printf("错误: 输入文件不是 .pkg 格式\n");
                return 1;
            }
        } else {
            NSArray *contents = [fm contentsOfDirectoryAtPath:inputPath error:nil];
            NSMutableArray *pkgFiles = [NSMutableArray array];
            for (NSString *item in contents) {
                if ([[[item pathExtension] lowercaseString] isEqualToString:@"pkg"]) {
                    [pkgFiles addObject:[inputPath stringByAppendingPathComponent:item]];
                }
            }
            if (pkgFiles.count == 0) {
                if (isDebug) printf("错误: 文件夹中未找到 .pkg 文件\n");
                return 1;
            }
            if (pkgFiles.count > 1) {
                if (isDebug) printf("错误: 文件夹中包含多个 .pkg 文件\n");
                return 1;
            }
            pkgFile = pkgFiles[0];
        }
        
        if (isDebug) printf("正在处理: %s\n", [pkgFile UTF8String]);
        
        PkgReader *reader = [[PkgReader alloc] initWithFilepath:pkgFile];
        if (!reader) {
            if (isDebug) printf("解析失败\n");
            return 1;
        }
        
        if (isInfo) {
            NSString *jsonPath = [[pkgFile stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"];
            if (outputPath) {
                BOOL outIsDir = NO;
                if ([fm fileExistsAtPath:outputPath isDirectory:&outIsDir] && outIsDir) {
                     jsonPath = [[outputPath stringByAppendingPathComponent:[[pkgFile lastPathComponent] stringByDeletingPathExtension]] stringByAppendingPathExtension:@"json"];
                } else if (![fm fileExistsAtPath:outputPath] && [[outputPath pathExtension] length] == 0) {
                    [fm createDirectoryAtPath:outputPath withIntermediateDirectories:YES attributes:nil error:nil];
                    jsonPath = [[outputPath stringByAppendingPathComponent:[[pkgFile lastPathComponent] stringByDeletingPathExtension]] stringByAppendingPathExtension:@"json"];
                } else {
                     jsonPath = outputPath;
                }
            }
            
            NSDictionary *info = [reader dumpInfo];
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:info options:NSJSONWritingPrettyPrinted error:nil];
            [jsonData writeToFile:jsonPath atomically:YES];
            if (isDebug) printf("详情已导出至: %s\n", [jsonPath UTF8String]);
        } else {
            NSString *outputDir = [pkgFile stringByDeletingLastPathComponent];
            if (outputPath) {
                outputDir = outputPath;
            }
            
            if (isDebug) printf("正在解包到: %s\n", [outputDir UTF8String]);
            if (![fm fileExistsAtPath:outputDir]) {
                NSError *dirError = nil;
                if (![fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:&dirError]) {
                    if (isDebug) printf("无法创建输出目录: %s\n", [[dirError localizedDescription] UTF8String]);
                    outputDir = [pkgFile stringByDeletingLastPathComponent];
                    if (isDebug) printf("回退到默认目录: %s\n", [outputDir UTF8String]);
                }
            }
            
            NSInteger successCount = 0;
            NSInteger total = reader.entries.count;
            for (NSInteger i = 0; i < total; i++) {
                if (isDebug && i % 50 == 0) {
                    printf("进度: %ld/%ld...\n", (long)i, (long)total);
                }
                if ([reader extractEntry:reader.entries[i] toOutputDir:outputDir]) {
                    successCount++;
                } else {
                    if (isDebug) printf("提取失败: %s\n", [reader.entries[i].path UTF8String]);
                }
            }
            
            NSString *srcDir = [pkgFile stringByDeletingLastPathComponent];
            if (![srcDir isEqualToString:outputDir]) {
                NSString *projJsonSrc = [srcDir stringByAppendingPathComponent:@"project.json"];
                if ([fm fileExistsAtPath:projJsonSrc]) {
                    NSString *projJsonDst = [outputDir stringByAppendingPathComponent:@"project.json"];
                    [fm copyItemAtPath:projJsonSrc toPath:projJsonDst error:nil];
                    
                    NSData *pData = [NSData dataWithContentsOfFile:projJsonSrc];
                    if (pData) {
                        NSDictionary *pDict = [NSJSONSerialization JSONObjectWithData:pData options:0 error:nil];
                        if ([pDict isKindOfClass:[NSDictionary class]]) {
                            NSString *previewName = pDict[@"preview"];
                            if (previewName && [previewName isKindOfClass:[NSString class]]) {
                                NSString *prevSrc = [srcDir stringByAppendingPathComponent:previewName];
                                if ([fm fileExistsAtPath:prevSrc]) {
                                    NSString *prevDst = [outputDir stringByAppendingPathComponent:previewName];
                                    [fm copyItemAtPath:prevSrc toPath:prevDst error:nil];
                                    if (isDebug) printf("已复制 project.json 和 %s 到输出目录\n", [previewName UTF8String]);
                                }
                            } else {
                                if (isDebug) printf("已复制 project.json 到输出目录\n");
                            }
                        }
                    }
                } else {
                    if (isDebug) printf("未找到 project.json\n");
                }
            }
            
            if (isDebug) printf("完成。成功提取 %ld/%ld 个文件。\n", (long)successCount, (long)total);
        }
    }
    return 0;
}