#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface BinaryReader : NSObject
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) NSUInteger pos;
@property (nonatomic, assign) NSUInteger size;
- (instancetype)initWithData:(NSData *)data;
- (void)seek:(NSUInteger)offset;
- (void)skip:(NSUInteger)amount;
- (NSData *)readBytes:(NSUInteger)count;
- (int32_t)readInt32;
- (uint32_t)readUInt32;
- (int16_t)readInt16;
- (uint16_t)readUInt16;
- (float)readFloat;
- (NSString *)readString;
- (void)readVersionWithPrefix:(NSString *)prefix completion:(void(^)(int version, NSString *rawVer))completion;
@end

@implementation BinaryReader
- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _data = data;
        _pos = 0;
        _size = data.length;
    }
    return self;
}
- (void)seek:(NSUInteger)offset {
    _pos = offset;
}
- (void)skip:(NSUInteger)amount {
    _pos += amount;
}
- (NSData *)readBytes:(NSUInteger)count {
    if (_pos + count > _size) {
        count = _size - _pos;
        if (count <= 0) {
            @throw [NSException exceptionWithName:@"EOFError" reason:@"Unexpected end of file" userInfo:nil];
        }
    }
    NSData *sub = [_data subdataWithRange:NSMakeRange(_pos, count)];
    _pos += count;
    return sub;
}
- (int32_t)readInt32 {
    int32_t val;
    [[self readBytes:4] getBytes:&val length:4];
    return val;
}
- (uint32_t)readUInt32 {
    uint32_t val;
    [[self readBytes:4] getBytes:&val length:4];
    return val;
}
- (int16_t)readInt16 {
    int16_t val;
    [[self readBytes:2] getBytes:&val length:2];
    return val;
}
- (uint16_t)readUInt16 {
    uint16_t val;
    [[self readBytes:2] getBytes:&val length:2];
    return val;
}
- (float)readFloat {
    float val;
    [[self readBytes:4] getBytes:&val length:4];
    return val;
}
- (NSString *)readString {
    NSUInteger startPos = _pos;
    const char *bytes = (const char *)_data.bytes;
    while (_pos < _size) {
        if (bytes[_pos] == 0) {
            break;
        }
        _pos++;
    }
    NSData *strData = [_data subdataWithRange:NSMakeRange(startPos, _pos - startPos)];
    _pos++;
    NSString *res = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
    if (!res) {
        NSStringEncoding gbkEncoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
        res = [[NSString alloc] initWithData:strData encoding:gbkEncoding];
        if (!res) {
            res = [[NSString alloc] initWithData:strData encoding:NSASCIIStringEncoding];
        }
    }
    return res ?: @"";
}
- (void)readVersionWithPrefix:(NSString *)prefix completion:(void(^)(int version, NSString *rawVer))completion {
    @try {
        NSData *raw = [self readBytes:9];
        const char *bytes = raw.bytes;
        size_t len = 0;
        while(len < raw.length && bytes[len] != 0) len++;
        NSString *sRaw = [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
        if (!sRaw) sRaw = @"INVALID";
        if (![sRaw hasPrefix:prefix]) {
            completion(0, sRaw);
            return;
        }
        if (sRaw.length >= 8) {
            NSString *verPart = [sRaw substringWithRange:NSMakeRange(4, 4)];
            int ver = [verPart intValue];
            completion(ver, sRaw);
        } else {
            completion(0, sRaw);
        }
    } @catch (NSException *e) {
        completion(0, @"EOF");
    }
}
@end

@interface MDLParser : NSObject
+ (void)parseFile:(NSString *)filePath;
@end

@implementation MDLParser
+ (NSUInteger)findSignatureOffset:(NSData *)data signature:(NSString *)signature startOffset:(NSUInteger)startOffset {
    NSData *searchData = [signature dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [data rangeOfData:searchData options:0 range:NSMakeRange(startOffset, data.length - startOffset)];
    if (range.location == NSNotFound) return -1;
    return range.location;
}
+ (void)parseFile:(NSString *)filePath {
    printf("--------------------------------------------------\n");
    printf("Processing: %s\n", [filePath lastPathComponent].UTF8String);
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        printf("[ERROR] File not found: %s\n", filePath.UTF8String);
        return;
    }
    NSString *fileDir = [filePath stringByDeletingLastPathComponent];
    NSString *baseName = [[filePath lastPathComponent] stringByDeletingPathExtension];
    NSString *outputObj = [fileDir stringByAppendingPathComponent:[baseName stringByAppendingString:@".obj"]];
    NSString *outputJson = [fileDir stringByAppendingPathComponent:[baseName stringByAppendingString:@"_data.json"]];
    BinaryReader *reader = [[BinaryReader alloc] initWithData:data];
    
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
    infoDict[@"generator"] = @"MDL Parser by laobamac (Modified)";
    
    NSMutableArray *skinning = [NSMutableArray array];
    NSMutableArray *skeleton = [NSMutableArray array];
    NSMutableArray *animations = [NSMutableArray array];
    NSMutableArray *objVertices = [NSMutableArray array];
    NSMutableArray *objUvs = [NSMutableArray array];
    NSMutableArray *objFaces = [NSMutableArray array];
    NSMutableArray *clippingMasks = [NSMutableArray array];
    NSMutableArray *subMeshes = [NSMutableArray array];
    NSMutableArray *maskBindings = [NSMutableArray array];
    
    NSData *searchData = [@"masks/" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange searchRange = NSMakeRange(0, data.length);
    while (searchRange.location < data.length) {
        NSRange foundRange = [data rangeOfData:searchData options:0 range:searchRange];
        if (foundRange.location == NSNotFound) break;
        
        NSUInteger start = foundRange.location;
        NSUInteger end = start;
        const char *bytes = data.bytes;
        while (end < data.length && bytes[end] != '\0') {
            end++;
        }
        
        NSData *strData = [data subdataWithRange:NSMakeRange(start, end - start)];
        NSString *maskPath = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
        
        if (maskPath && [maskPath containsString:@"clipping_mask"] && ![clippingMasks containsObject:maskPath]) {
            [clippingMasks addObject:maskPath];
            printf("  Found Clipping Mask: %s\n", maskPath.UTF8String);
        }
        
        if (end + 1 >= data.length) break;
        searchRange.location = end + 1;
        searchRange.length = data.length - searchRange.location;
    }

    NSUInteger mdlsOffset = [self findSignatureOffset:data signature:@"MDLS" startOffset:0];

    @try {
        __block int mdlVersion = 0;
        __block NSString *rawVer = @"";
        [reader readVersionWithPrefix:@"MDL" completion:^(int v, NSString *r) {
            mdlVersion = v;
            rawVer = r;
        }];
        printf("MDL Version: %d (Raw: %s)\n", mdlVersion, rawVer.UTF8String);
        int32_t mdlFlag = [reader readInt32];
        [reader readInt32];
        [reader readInt32];
        NSString *matJsonFile = [reader readString];
        [reader readInt32];
        infoDict[@"version"] = @(mdlVersion);
        infoDict[@"flag"] = @(mdlFlag);
        infoDict[@"material_file"] = matJsonFile;
        BOOL altMdlFormat = NO;
        uint32_t curr = [reader readUInt32];
        uint32_t stdHerald = 0x01800009;
        uint32_t altHerald = 0x0180000F;
        if (curr == 0) {
            altMdlFormat = YES;
            printf("Format: Alternative MDL\n");
            while (curr != altHerald && reader.pos < reader.size) {
                curr = [reader readUInt32];
            }
            curr = [reader readUInt32];
        } else if (curr == stdHerald) {
            curr = [reader readUInt32];
        }
        uint32_t vertexSize = curr;
        uint32_t stride = altMdlFormat ? 80 : 52;
        if (stride == 0 || (vertexSize % stride != 0)) {
            printf("[WARN] Vertex size alignment issue. Size: %u, Stride: %u\n", vertexSize, stride);
        }
        uint32_t vertexCount = vertexSize / stride;
        printf("Vertices: %u\n", vertexCount);
        for (uint32_t i = 0; i < vertexCount; i++) {
            float vx = [reader readFloat];
            float vy = [reader readFloat];
            float vz = [reader readFloat];
            [objVertices addObject:@[@(vx), @(vy), @(vz)]];
            if (altMdlFormat) {
                [reader readBytes:28];
            }
            NSArray *bIndices = @[@([reader readUInt32]), @([reader readUInt32]), @([reader readUInt32]), @([reader readUInt32])];
            NSArray *weights = @[@([reader readFloat]), @([reader readFloat]), @([reader readFloat]), @([reader readFloat])];
            [skinning addObject:@{
                @"vertex_id": @(i),
                @"bone_indices": bIndices,
                @"weights": weights
            }];
            float tu = [reader readFloat];
            float tv = [reader readFloat];
            [objUvs addObject:@[@(tu), @(tv)]];
        }
        uint32_t indicesSize = [reader readUInt32];
        uint32_t triCount = indicesSize / 6;
        printf("Triangles: %u\n", triCount);
        for (uint32_t i = 0; i < triCount; i++) {
            uint16_t f1 = [reader readUInt16];
            uint16_t f2 = [reader readUInt16];
            uint16_t f3 = [reader readUInt16];
            [objFaces addObject:@[@(f1), @(f2), @(f3)]];
        }

        NSUInteger currentPos = reader.pos;
        NSUInteger searchLimit = mdlsOffset != -1 ? mdlsOffset : data.length;
        
        [reader seek:currentPos];
        while (reader.pos + 16 <= searchLimit) {
            uint32_t gId = [reader readUInt32];
            uint32_t gFlag = [reader readUInt32];
            uint32_t gStart = [reader readUInt32];
            uint32_t gCount = [reader readUInt32];
            
            BOOL isValid = (gId > 0 && gId < 250 && 
                            gFlag == 0 && 
                            gCount > 0 && gCount < 10000000 && 
                            (gStart % 3 == 0) && (gCount % 3 == 0));
            
            if (subMeshes.count == 0 && gStart != 0) {
                isValid = NO;
            }
            
            if (isValid) {
                [subMeshes addObject:@{@"id": @(gId), @"flag": @(gFlag), @"start": @(gStart), @"count": @(gCount)}];
            } else {
                if (subMeshes.count > 0) {
                    break;
                } else {
                    [reader seek:reader.pos - 15];
                }
            }
        }
        
        NSData *maskSearchData = [@"masks/" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange maskSearchRange = NSMakeRange(currentPos, searchLimit - currentPos);
        while (maskSearchRange.location < searchLimit) {
            NSRange foundRange = [data rangeOfData:maskSearchData options:0 range:maskSearchRange];
            if (foundRange.location == NSNotFound) break;
            
            [reader seek:foundRange.location];
            NSString *mPath = [reader readString];
            
            uint32_t targetId = 0;
            for (int k = 0; k < 64 && reader.pos + 4 <= reader.size; k++) {
                uint32_t val = [reader readUInt32];
                if (val == 1) {
                    targetId = [reader readUInt32];
                    break;
                }
                [reader seek:reader.pos - 3];
            }
            
            if (mPath.length > 0 && targetId > 0 && targetId < 10000) {
                BOOL exists = NO;
                for (NSDictionary *d in maskBindings) {
                    if ([d[@"path"] isEqualToString:mPath] && [d[@"target_group"] unsignedIntValue] == targetId) {
                        exists = YES; break;
                    }
                }
                if (!exists) {
                    [maskBindings addObject:@{@"path": mPath, @"target_group": @(targetId)}];
                }
            }
            
            maskSearchRange.location = reader.pos;
            if (maskSearchRange.location >= searchLimit) break;
            maskSearchRange.length = searchLimit - maskSearchRange.location;
        }

    } @catch (NSException *e) {
        printf("[ERROR] Mesh parsing failed: %s\n", e.reason.UTF8String);
    }
    
    if (mdlsOffset != -1) {
        printf("\nFound MDLS at offset %lu. Parsing Skeleton...\n", (unsigned long)mdlsOffset);
        [reader seek:mdlsOffset];
        @try {
            __block int mdlsVer = 0;
            [reader readVersionWithPrefix:@"MDL" completion:^(int v, NSString *r) { mdlsVer = v; }];
            [reader readUInt32];
            uint16_t boneCount = [reader readUInt16];
            [reader readUInt16];
            printf("  Skeleton Ver: %d, Bones: %d\n", mdlsVer, boneCount);
            if (boneCount > 0 && boneCount < 10000) {
                for (int i = 0; i < boneCount; i++) {
                    NSString *boneName = [reader readString];
                    [reader readInt32];
                    uint32_t parent = [reader readUInt32];
                    uint32_t size = [reader readUInt32];
                    NSMutableArray *matrix = [NSMutableArray array];
                    if (size == 64) {
                        for (int k = 0; k < 16; k++) [matrix addObject:@([reader readFloat])];
                    } else {
                        [reader readBytes:size];
                    }
                    NSString *simJson = [reader readString];
                    [skeleton addObject:@{
                        @"id": @(i),
                        @"name": boneName,
                        @"parent": @(parent),
                        @"matrix": matrix,
                        @"sim_config": simJson,
                        @"render_tag": [NSNull null]
                    }];
                }
                printf("  Skeleton parsed successfully.\n");
            } else {
                printf("  [WARN] Suspicious bone count, skipping skeleton.\n");
            }
        } @catch (NSException *e) {
            printf("  [WARN] Skeleton parsing interrupted: %s\n", e.reason.UTF8String);
        }
    } else {
        printf("\nMDLS signature not found.\n");
    }
    
    NSUInteger mdlaOffset = [self findSignatureOffset:data signature:@"MDLA" startOffset:0];
    if (mdlaOffset != -1) {
        printf("\nFound MDLA at offset %lu. Parsing Animations...\n", (unsigned long)mdlaOffset);
        [reader seek:mdlaOffset];
        @try {
            __block int mdlaVer = 0;
            __block NSString *mdlaRaw = @"";
            [reader readVersionWithPrefix:@"MDL" completion:^(int v, NSString *r) { mdlaVer = v; mdlaRaw = r; }];
            printf("  Animation Ver: %d (Raw: %s)\n", mdlaVer, mdlaRaw.UTF8String);
            if (mdlaVer > 0) {
                [reader readUInt32];
                uint32_t animNum = [reader readUInt32];
                printf("  Animation Count: %u\n", animNum);
                if (animNum > 10000) {
                    printf("  [WARN] Animation count too high, skipping.\n");
                    animNum = 0;
                }
                for (uint32_t i = 0; i < animNum; i++) {
                    @try {
                        int32_t animId = 0;
                        while (animId == 0) {
                            if (reader.pos >= reader.size - 4) break;
                            animId = [reader readInt32];
                        }
                        if (animId == 0) break;
                        [reader readInt32];
                        NSString *animName = [reader readString];
                        if (animName.length == 0) animName = [reader readString];
                        NSString *playMode = [reader readString];
                        float fps = [reader readFloat];
                        int32_t length = [reader readInt32];
                        [reader readInt32];
                        uint32_t boneFramesCount = [reader readUInt32];
                        NSMutableDictionary *animEntry = [NSMutableDictionary dictionary];
                        animEntry[@"id"] = @(animId);
                        animEntry[@"name"] = animName;
                        animEntry[@"mode"] = playMode;
                        animEntry[@"fps"] = @(fps);
                        animEntry[@"length"] = @(length);
                        animEntry[@"track_count"] = @(boneFramesCount);
                        NSMutableArray *tracks = [NSMutableArray array];
                        
                        for (uint32_t j = 0; j < boneFramesCount; j++) {
                            int32_t trackHeaderVal = [reader readInt32]; 
                            (void)trackHeaderVal;
                            
                            uint32_t byteSize = [reader readUInt32];
                            if (reader.pos + byteSize > reader.size) {
                                printf("    [ERR] Track %u size %u exceeds file bounds.\n", j, byteSize);
                                [reader seek:reader.size];
                                break;
                            }
                            NSUInteger framesNum = byteSize / 36;
                            NSMutableArray *frames = [NSMutableArray array];
                            for (int k = 0; k < framesNum; k++) {
                                NSArray *p = @[@([reader readFloat]), @([reader readFloat]), @([reader readFloat])];
                                NSArray *r = @[@([reader readFloat]), @([reader readFloat]), @([reader readFloat])];
                                NSArray *s = @[@([reader readFloat]), @([reader readFloat]), @([reader readFloat])];
                                [frames addObject:@{@"p": p, @"r": r, @"s": s}];
                            }
                            NSUInteger remainder = byteSize - (framesNum * 36);
                            if (remainder > 0) [reader readBytes:remainder];
                            
                            [tracks addObject:[NSMutableDictionary dictionaryWithDictionary:@{
                                @"track_id": @(j), 
                                @"frames": frames,
                                @"_debug_header_val": @(trackHeaderVal) 
                            }]];
                        }
                        
                        animEntry[@"tracks"] = tracks;
                        [animations addObject:animEntry];
                    } @catch (NSException *e) {
                        printf("  [WARN] Error parsing animation %u: %s. Skipping.\n", i, e.reason.UTF8String);
                        continue;
                    }
                }
                printf("  Parsed %lu animations.\n", (unsigned long)animations.count);
            }
        } @catch (NSException *e) {
            printf("  [WARN] MDLA header parsing failed: %s\n", e.reason.UTF8String);
        }
    } else {
        printf("\nMDLA signature not found.\n");
    }
    
    @try {
        NSMutableString *objContent = [NSMutableString string];
        [objContent appendFormat:@"# Exported from %@ by laobamac MDL Parser\n", [filePath lastPathComponent]];
        NSString *mtlName = @"unknown.mtl";
        if (infoDict[@"material_file"]) {
            mtlName = [infoDict[@"material_file"] stringByReplacingOccurrencesOfString:@".json" withString:@".mtl"];
        }
        [objContent appendFormat:@"mtllib %@\n", [mtlName lastPathComponent]];
        for (NSArray *v in objVertices) {
            [objContent appendFormat:@"v %.6f %.6f %.6f\n", [v[0] floatValue], [v[1] floatValue], [v[2] floatValue]];
        }
        for (NSArray *uv in objUvs) {
            [objContent appendFormat:@"vt %.6f %.6f\n", [uv[0] floatValue], [uv[1] floatValue]];
        }
        
        if (subMeshes.count > 0) {
            for (NSUInteger idx = 0; idx < subMeshes.count; idx++) {
                NSDictionary *sm = subMeshes[idx];
                uint32_t gId = [sm[@"id"] unsignedIntValue];
                uint32_t gStart = [sm[@"start"] unsignedIntValue] / 3;
                uint32_t gCount = [sm[@"count"] unsignedIntValue] / 3;
                
                NSString *groupName = [NSString stringWithFormat:@"Group_%u", gId];
                NSString *matName = [NSString stringWithFormat:@"Material_Group_%u", gId];
                
                for (NSDictionary *mb in maskBindings) {
                    if ([mb[@"target_group"] unsignedIntValue] == idx) {
                        NSString *safePath = [[mb[@"path"] lastPathComponent] stringByDeletingPathExtension];
                        groupName = [NSString stringWithFormat:@"Group_%u_%@", gId, safePath];
                        matName = [NSString stringWithFormat:@"Masked_%@", safePath];
                        break;
                    }
                }
                
                [objContent appendFormat:@"g %@\n", groupName];
                [objContent appendFormat:@"usemtl %@\n", matName];
                
                for (uint32_t i = gStart; i < gStart + gCount && i < objFaces.count; i++) {
                    NSArray *f = objFaces[i];
                    int f1 = [f[0] intValue] + 1;
                    int f2 = [f[1] intValue] + 1;
                    int f3 = [f[2] intValue] + 1;
                    [objContent appendFormat:@"f %d/%d %d/%d %d/%d\n", f1, f1, f2, f2, f3, f3];
                }
            }
        } else {
            [objContent appendString:@"g Default\nusemtl Default\n"];
            for (NSArray *f in objFaces) {
                int f1 = [f[0] intValue] + 1;
                int f2 = [f[1] intValue] + 1;
                int f3 = [f[2] intValue] + 1;
                [objContent appendFormat:@"f %d/%d %d/%d %d/%d\n", f1, f1, f2, f2, f3, f3];
            }
        }
        
        NSError *writeErr = nil; 
        [objContent writeToFile:outputObj atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
        if (writeErr) {
             printf("[ERROR] Could not save OBJ: %s\n", writeErr.localizedDescription.UTF8String);
        } else {
             printf("\n[SUCCESS] OBJ saved to: %s\n", outputObj.UTF8String);
        }
    } @catch (NSException *e) {
        printf("[ERROR] Could not save OBJ: %s\n", e.reason.UTF8String);
    }
    
    @try {
        NSError *jsonErr = nil; 
        NSData *infoData = [NSJSONSerialization dataWithJSONObject:infoDict options:NSJSONWritingPrettyPrinted error:&jsonErr];
        NSData *masksData = [NSJSONSerialization dataWithJSONObject:clippingMasks options:NSJSONWritingPrettyPrinted error:&jsonErr];
        NSData *subMeshesData = [NSJSONSerialization dataWithJSONObject:subMeshes options:NSJSONWritingPrettyPrinted error:&jsonErr];
        NSData *maskBindingsData = [NSJSONSerialization dataWithJSONObject:maskBindings options:NSJSONWritingPrettyPrinted error:&jsonErr];
        NSData *skinningData = [NSJSONSerialization dataWithJSONObject:skinning options:NSJSONWritingPrettyPrinted error:&jsonErr];
        NSData *skeletonData = [NSJSONSerialization dataWithJSONObject:skeleton options:NSJSONWritingPrettyPrinted error:&jsonErr];
        NSData *animationsData = [NSJSONSerialization dataWithJSONObject:animations options:NSJSONWritingPrettyPrinted error:&jsonErr];

        if (!infoData || !masksData || !subMeshesData || !maskBindingsData || !skinningData || !skeletonData || !animationsData) {
             printf("[ERROR] JSON serialization failed: %s\n", jsonErr ? jsonErr.localizedDescription.UTF8String : "Unknown Error");
        } else {
            NSString *infoStr = [[NSString alloc] initWithData:infoData encoding:NSUTF8StringEncoding];
            NSString *masksStr = [[NSString alloc] initWithData:masksData encoding:NSUTF8StringEncoding];
            NSString *subMeshesStr = [[NSString alloc] initWithData:subMeshesData encoding:NSUTF8StringEncoding];
            NSString *maskBindingsStr = [[NSString alloc] initWithData:maskBindingsData encoding:NSUTF8StringEncoding];
            NSString *skinningStr = [[NSString alloc] initWithData:skinningData encoding:NSUTF8StringEncoding];
            NSString *skeletonStr = [[NSString alloc] initWithData:skeletonData encoding:NSUTF8StringEncoding];
            NSString *animationsStr = [[NSString alloc] initWithData:animationsData encoding:NSUTF8StringEncoding];
            
            NSString *finalJson = [NSString stringWithFormat:@"{\n  \"info\": %@,\n  \"clipping_masks\": %@,\n  \"sub_meshes\": %@,\n  \"mask_bindings\": %@,\n  \"skinning\": %@,\n  \"skeleton\": %@,\n  \"animations\": %@\n}", infoStr, masksStr, subMeshesStr, maskBindingsStr, skinningStr, skeletonStr, animationsStr];
            
            jsonErr = nil; 
            [finalJson writeToFile:outputJson atomically:YES encoding:NSUTF8StringEncoding error:&jsonErr];
            if (jsonErr) {
                 printf("[ERROR] Could not save JSON: %s\n", jsonErr.localizedDescription.UTF8String);
            } else {
                 printf("[SUCCESS] Extra data saved to: %s\n", outputJson.UTF8String);
            }
        }
    } @catch (NSException *e) {
        printf("[ERROR] Could not save JSON: %s\n", e.reason.UTF8String);
    }
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL isSecretDebug = NO;
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "-d") == 0) {
                isSecretDebug = YES;
                break;
            }
        }

        if (!isSecretDebug) {
            pid_t parentPID = getppid();
            NSRunningApplication *parentApp = [NSRunningApplication runningApplicationWithProcessIdentifier:parentPID];
            NSString *parentBundleID = [parentApp bundleIdentifier];

            if (!parentBundleID || ![parentBundleID isEqualToString:@"cn.laobamacOpenMetalWallpaper"]) {
                printf("[ERROR] Access Denied: Unauthorized invocation.\n");
                return 100;
            }
        }

        if (argc < 2) {
            printf("Usage: ./mdl_parser <input.mdl> OR <directory>\n");
            return 1;
        }

        NSMutableArray *args = [NSMutableArray array];
        
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"-d"]) {
                continue; 
            }
            else {
                [args addObject:arg];
            }
        }

        if (args.count == 0) {
            printf("[ERROR] No input file specified.\n");
            return 1;
        }

        NSString *inputPath = args[0];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDir = NO;
        
        if ([fm fileExistsAtPath:inputPath isDirectory:&isDir]) {
            if (isDir) {
                NSString *sceneJsonPath = [inputPath stringByAppendingPathComponent:@"scene.json"];
                if ([fm fileExistsAtPath:sceneJsonPath]) {
                    NSString *modelsPath = [inputPath stringByAppendingPathComponent:@"models"];
                    if ([fm fileExistsAtPath:modelsPath]) {
                        printf("Found scene.json. Switching scan directory to: %s\n", modelsPath.UTF8String);
                        inputPath = modelsPath;
                    }
                }
                printf("Scanning directory: %s\n", inputPath.UTF8String);
                NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:inputPath];
                NSString *file;
                BOOL found = NO;
                while (file = [enumerator nextObject]) {
                    if ([[file pathExtension] caseInsensitiveCompare:@"mdl"] == NSOrderedSame) {
                        found = YES;
                        [MDLParser parseFile:[inputPath stringByAppendingPathComponent:file]];
                    }
                }
                if (!found) printf("No .mdl files found in directory.\n");
            } else {
                [MDLParser parseFile:inputPath];
            }
        } else {
            printf("[ERROR] Invalid path: %s\n", inputPath.UTF8String);
        }
    }
    return 0;
}