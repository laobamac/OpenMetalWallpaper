import sys
import struct
import io
import math
import os
import argparse
import json
import dataclasses
import shutil
from enum import IntEnum, IntFlag
from dataclasses import dataclass, field
from typing import List, Optional, Any, Tuple
from PIL import Image
import lz4.block
import texture2ddecoder
import numpy as np

try:
    from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                                 QHBoxLayout, QLabel, QScrollArea, QPushButton,
                                 QFileDialog, QSplitter, QTextEdit, QFrame, QMessageBox,
                                 QSizePolicy, QCheckBox)
    from PyQt6.QtCore import Qt, QTimer
    from PyQt6.QtGui import QPixmap, QImage, QDragEnterEvent, QDropEvent, QAction
    GUI_AVAILABLE = True
except ImportError:
    GUI_AVAILABLE = False

# --- 枚举与数据结构 ---

class TexFormat(IntEnum):
    RGBA8888 = 0
    DXT5 = 4
    DXT3 = 6
    DXT1 = 7
    RG88 = 8
    R8 = 9

class TexFlags(IntFlag):
    None_ = 0
    NoInterpolation = 1
    ClampUVs = 2
    IsGif = 4
    IsVideoTexture = 32

class FreeImageFormat(IntEnum):
    FIF_UNKNOWN = -1
    FIF_BMP = 0
    FIF_ICO = 1
    FIF_JPEG = 2
    FIF_JNG = 3
    FIF_KOALA = 4
    FIF_LBM = 5
    FIF_MNG = 6
    FIF_PBM = 7
    FIF_PBMRAW = 8
    FIF_PCD = 9
    FIF_PCX = 10
    FIF_PGM = 11
    FIF_PGMRAW = 12
    FIF_PNG = 13
    FIF_PPM = 14
    FIF_PPMRAW = 15
    FIF_RAS = 16
    FIF_TARGA = 17
    FIF_TIFF = 18
    FIF_WBMP = 19
    FIF_PSD = 20
    FIF_CUT = 21
    FIF_XBM = 22
    FIF_XPM = 23
    FIF_DDS = 24
    FIF_GIF = 25
    FIF_HDR = 26
    FIF_FAXG3 = 27
    FIF_SGI = 28
    FIF_EXR = 29
    FIF_J2K = 30
    FIF_JP2 = 31
    FIF_PFM = 32
    FIF_PICT = 33
    FIF_RAW = 34
    FIF_MP4 = 35

class TexImageContainerVersion(IntEnum):
    Version1 = 1
    Version2 = 2
    Version3 = 3
    Version4 = 4

class MipmapFormat(IntEnum):
    Invalid = 0
    RGBA8888 = 1
    R8 = 2
    RG88 = 3
    CompressedDXT5 = 4
    CompressedDXT3 = 5
    CompressedDXT1 = 6
    VideoMp4 = 7
    ImagePNG = 1013
    ImageGIF = 1025
    ImageJPEG = 1002

@dataclass
class TexHeader:
    format: TexFormat
    flags: TexFlags
    texture_width: int
    texture_height: int
    image_width: int
    image_height: int
    unk_int0: int

@dataclass
class TexMipmap:
    width: int
    height: int
    is_lz4_compressed: bool
    decompressed_bytes_count: int
    bytes_data: bytes = field(repr=False)
    format: MipmapFormat = MipmapFormat.Invalid

@dataclass
class TexImage:
    mipmaps: List[TexMipmap] = field(default_factory=list)

@dataclass
class TexImageContainer:
    magic: str
    image_format: FreeImageFormat
    version: TexImageContainerVersion
    images: List[TexImage] = field(default_factory=list)

@dataclass
class TexFrameInfo:
    image_id: int
    frametime: float
    x: float
    y: float
    width: float
    width_y: float
    height_x: float
    height: float

@dataclass
class TexFrameInfoContainer:
    magic: str
    gif_width: int
    gif_height: int
    frames: List[TexFrameInfo] = field(default_factory=list)

@dataclass
class TexFile:
    magic1: str
    magic2: str
    header: TexHeader
    image_container: TexImageContainer
    frame_info_container: Optional[TexFrameInfoContainer] = None

# --- 解析器 ---

class BinaryReader:
    def __init__(self, data: bytes):
        self.stream = io.BytesIO(data)
        self.data = data

    def read_int32(self) -> int:
        return struct.unpack('<i', self.stream.read(4))[0]
    
    def read_uint32(self) -> int:
        return struct.unpack('<I', self.stream.read(4))[0]

    def read_single(self) -> float:
        return struct.unpack('<f', self.stream.read(4))[0]

    def read_bytes(self, count: int) -> bytes:
        return self.stream.read(count)

    def read_n_string(self, max_length: int = -1) -> str:
        chars = []
        while True:
            char_byte = self.stream.read(1)
            if not char_byte: break
            if char_byte == b'\x00': break
            chars.append(char_byte.decode('utf-8', errors='ignore'))
            if max_length > 0 and len(chars) >= max_length: break
        return "".join(chars)

class TexParser:
    @staticmethod
    def parse(file_path: str) -> TexFile:
        with open(file_path, 'rb') as f:
            data = f.read()
        
        reader = BinaryReader(data)
        
        magic1 = reader.read_n_string(16)
        if magic1 != "TEXV0005":
            raise ValueError(f"无效的文件头 Magic1: {magic1}")
            
        magic2 = reader.read_n_string(16)
        if magic2 != "TEXI0001":
            raise ValueError(f"无效的文件头 Magic2: {magic2}")

        header = TexParser._read_header(reader)
        image_container = TexParser._read_image_container(reader, header.format)

        frame_info = None
        if TexFlags.IsGif in header.flags:
            frame_info = TexParser._read_frame_info(reader)

        return TexFile(magic1, magic2, header, image_container, frame_info)

    @staticmethod
    def _read_header(reader: BinaryReader) -> TexHeader:
        fmt = TexFormat(reader.read_int32())
        flags = TexFlags(reader.read_int32())
        t_w = reader.read_int32()
        t_h = reader.read_int32()
        i_w = reader.read_int32()
        i_h = reader.read_int32()
        unk = reader.read_uint32()
        return TexHeader(fmt, flags, t_w, t_h, i_w, i_h, unk)

    @staticmethod
    def _read_image_container(reader: BinaryReader, tex_format: TexFormat) -> TexImageContainer:
        magic = reader.read_n_string(16)
        image_count = reader.read_int32()
        
        image_fmt = FreeImageFormat.FIF_UNKNOWN
        version = TexImageContainerVersion.Version1

        if magic == "TEXB0003":
            image_fmt = FreeImageFormat(reader.read_int32())
            version = TexImageContainerVersion.Version3
        elif magic == "TEXB0004":
            image_fmt = FreeImageFormat(reader.read_int32())
            is_video_mp4 = reader.read_int32() == 1
            if image_fmt == FreeImageFormat.FIF_UNKNOWN and is_video_mp4:
                image_fmt = FreeImageFormat.FIF_MP4
            version = TexImageContainerVersion.Version4
        else:
            try:
                ver_num = int(magic[4:])
                version = TexImageContainerVersion(ver_num)
            except:
                pass

        if version == TexImageContainerVersion.Version4 and image_fmt != FreeImageFormat.FIF_MP4:
            version = TexImageContainerVersion.Version3

        images = []
        for _ in range(image_count):
            images.append(TexParser._read_image(reader, version, image_fmt, tex_format))
        
        return TexImageContainer(magic, image_fmt, version, images)

    @staticmethod
    def _read_image(reader: BinaryReader, version: TexImageContainerVersion,
                   container_fmt: FreeImageFormat, tex_fmt: TexFormat) -> TexImage:
        mipmap_count = reader.read_int32()
        mipmaps = []
        mipmap_fmt = TexParser._get_mipmap_format(container_fmt, tex_fmt)

        for _ in range(mipmap_count):
            mm = TexParser._read_mipmap(reader, version)
            mm.format = mipmap_fmt
            if mm.is_lz4_compressed:
                try:
                    mm.bytes_data = lz4.block.decompress(mm.bytes_data, uncompressed_size=mm.decompressed_bytes_count)
                    mm.is_lz4_compressed = False
                except Exception as e:
                    print(f"[警告] LZ4 解压失败: {e}")
            mipmaps.append(mm)
        
        return TexImage(mipmaps)

    @staticmethod
    def _read_mipmap(reader: BinaryReader, version: TexImageContainerVersion) -> TexMipmap:
        width = reader.read_int32()
        height = reader.read_int32()
        is_lz4 = False
        decomp_len = 0
        
        if version in [TexImageContainerVersion.Version2, TexImageContainerVersion.Version3]:
            is_lz4 = reader.read_int32() == 1
            decomp_len = reader.read_int32()
        elif version == TexImageContainerVersion.Version4:
            reader.read_int32()
            reader.read_int32()
            reader.read_n_string()
            reader.read_int32()
            is_lz4 = reader.read_int32() == 1
            decomp_len = reader.read_int32()

        byte_count = reader.read_int32()
        data = reader.read_bytes(byte_count)

        if version == TexImageContainerVersion.Version1:
             decomp_len = byte_count

        return TexMipmap(width, height, is_lz4, decomp_len, data)

    @staticmethod
    def _read_frame_info(reader: BinaryReader) -> TexFrameInfoContainer:
        magic = reader.read_n_string(16)
        count = reader.read_int32()
        
        gif_w, gif_h = 0, 0
        if magic == "TEXS0003":
            gif_w = reader.read_int32()
            gif_h = reader.read_int32()

        frames = []
        is_float = magic in ["TEXS0002", "TEXS0003"]
        
        for _ in range(count):
            img_id = reader.read_int32()
            ft = reader.read_single()
            if is_float:
                x = reader.read_single()
                y = reader.read_single()
                w = reader.read_single()
                wy = reader.read_single()
                hx = reader.read_single()
                h = reader.read_single()
            else:
                x = float(reader.read_int32())
                y = float(reader.read_int32())
                w = float(reader.read_int32())
                wy = float(reader.read_int32())
                hx = float(reader.read_int32())
                h = float(reader.read_int32())
            
            frames.append(TexFrameInfo(img_id, ft, x, y, w, wy, hx, h))

        if gif_w == 0 and frames:
            gif_w = int(frames[0].width)
            gif_h = int(frames[0].height)

        return TexFrameInfoContainer(magic, gif_w, gif_h, frames)

    @staticmethod
    def _get_mipmap_format(container_fmt: FreeImageFormat, tex_fmt: TexFormat) -> MipmapFormat:
        if container_fmt != FreeImageFormat.FIF_UNKNOWN:
            if container_fmt == FreeImageFormat.FIF_MP4: return MipmapFormat.VideoMp4
            if container_fmt == FreeImageFormat.FIF_PNG: return MipmapFormat.ImagePNG
            if container_fmt == FreeImageFormat.FIF_JPEG: return MipmapFormat.ImageJPEG
            return MipmapFormat.ImagePNG
        
        map_ = {
            TexFormat.RGBA8888: MipmapFormat.RGBA8888,
            TexFormat.DXT5: MipmapFormat.CompressedDXT5,
            TexFormat.DXT3: MipmapFormat.CompressedDXT3,
            TexFormat.DXT1: MipmapFormat.CompressedDXT1,
            TexFormat.RG88: MipmapFormat.RG88,
            TexFormat.R8: MipmapFormat.R8
        }
        return map_.get(tex_fmt, MipmapFormat.Invalid)

class TexConverter:
    @staticmethod
    def to_image_and_duration(tex: TexFile, apply_fix_additive: bool = False) -> Tuple[List[Image.Image], List[int]]:
        """返回 (图像列表, 持续时间列表)"""
        if not tex.image_container.images:
            return [], []

        if TexFlags.IsVideoTexture in tex.header.flags:
            img = Image.new('RGB', (128, 128), color=(0, 0, 0))
            return [img], [100]

        images = []
        durations = []
        
        if TexFlags.IsGif in tex.header.flags and tex.frame_info_container:
            images, durations = TexConverter._process_gif(tex)
        else:
            first_img = tex.image_container.images[0]
            if first_img.mipmaps:
                images = [TexConverter._mipmap_to_pil(first_img.mipmaps[0])]
                durations = [100]
        
        if apply_fix_additive:
            images = [TexConverter.apply_additive_fix(img) for img in images]
            
        return images, durations

    @staticmethod
    def to_image(tex: TexFile, apply_fix_additive: bool = False) -> List[Image.Image]:
        # 兼容旧调用
        imgs, _ = TexConverter.to_image_and_duration(tex, apply_fix_additive)
        return imgs

    @staticmethod
    def _mipmap_to_pil(mipmap: TexMipmap) -> Image.Image:
        data = mipmap.bytes_data
        w, h = mipmap.width, mipmap.height
        
        if mipmap.format == MipmapFormat.RGBA8888:
            return Image.frombytes("RGBA", (w, h), data)
        elif mipmap.format == MipmapFormat.RG88:
            arr = np.frombuffer(data, dtype=np.uint8).reshape((h, w, 2))
            r = arr[:,:,0]
            g = arr[:,:,1]
            rgba = np.dstack((g, g, g, r))
            return Image.fromarray(rgba, 'RGBA')
        elif mipmap.format == MipmapFormat.R8:
            return Image.frombytes("L", (w, h), data)
        elif mipmap.format == MipmapFormat.CompressedDXT1:
            decoded = texture2ddecoder.decode_bc1(data, w, h)
            return Image.frombytes("RGBA", (w, h), decoded, "raw", "BGRA")
        elif mipmap.format == MipmapFormat.CompressedDXT3:
            decoded = texture2ddecoder.decode_bc2(data, w, h)
            return Image.frombytes("RGBA", (w, h), decoded, "raw", "BGRA")
        elif mipmap.format == MipmapFormat.CompressedDXT5:
            decoded = texture2ddecoder.decode_bc3(data, w, h)
            return Image.frombytes("RGBA", (w, h), decoded, "raw", "BGRA")
        elif mipmap.format in [MipmapFormat.ImagePNG, MipmapFormat.ImageJPEG]:
            return Image.open(io.BytesIO(data))
        
        return Image.new('RGB', (w, h), color='red')

    @staticmethod
    def _process_gif(tex: TexFile) -> Tuple[List[Image.Image], List[int]]:
        base_images = []
        for img in tex.image_container.images:
            base_images.append(TexConverter._mipmap_to_pil(img.mipmaps[0]))

        canvas_w = tex.frame_info_container.gif_width
        canvas_h = tex.frame_info_container.gif_height

        processed_sprites = []
        processed_durations = []
        
        max_sprite_w, max_sprite_h = 0, 0
        temp_sprites_info = []

        for frame_info in tex.frame_info_container.frames:
            # 过滤无效尺寸
            width = frame_info.width if frame_info.width != 0 else frame_info.height_x
            height = frame_info.height if frame_info.height != 0 else frame_info.width_y
            
            if abs(width) < 1 or abs(height) < 1:
                continue

            x = min(frame_info.x, frame_info.x + width)
            y = min(frame_info.y, frame_info.y + height)
            sw = 1 if width >= 0 else -1
            sh = 1 if height >= 0 else -1
            angle_rad = -(math.atan2(sh, sw) - math.pi / 4.0)
            angle_deg = round(angle_rad * 180.0 / math.pi)

            if frame_info.image_id >= len(base_images):
                continue

            src_img = base_images[frame_info.image_id]
            crop_rect = (int(x), int(y), int(x + abs(width)), int(y + abs(height)))
            
            # 裁剪
            try:
                cropped = src_img.crop(crop_rect)
            except Exception:
                continue
            
            if angle_deg != 0:
                rotated = cropped.rotate(angle_deg, expand=True, resample=Image.BICUBIC)
            else:
                rotated = cropped
            
            # 记录精灵信息
            temp_sprites_info.append(rotated)
            max_sprite_w = max(max_sprite_w, rotated.width)
            max_sprite_h = max(max_sprite_h, rotated.height)
            
            # 记录时间 (修正逻辑)
            d = int(frame_info.frametime * 1000)
            if d <= 0: d = 100  # 默认 100ms
            if d < 45: d = 45   # 强制最小 45ms (~22fps) 防止过快
            processed_durations.append(d)

        if canvas_w <= 0: canvas_w = max_sprite_w
        if canvas_h <= 0: canvas_h = max_sprite_h
        canvas_w = max(1, canvas_w)
        canvas_h = max(1, canvas_h)

        final_frames = []
        final_durations = []

        # 合成
        for idx, sprite in enumerate(temp_sprites_info):
            canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
            paste_x = (canvas_w - sprite.width) // 2
            paste_y = (canvas_h - sprite.height) // 2
            canvas.paste(sprite, (paste_x, paste_y))
            
            if canvas.getbbox() is None:
                continue 
            
            final_frames.append(canvas)
            final_durations.append(processed_durations[idx])
            
        return final_frames, final_durations

    @staticmethod
    def apply_additive_fix(img: Image.Image) -> Image.Image:
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        arr = np.array(img)
        max_rgb = np.max(arr[:, :, :3], axis=2)
        arr[:, :, 3] = max_rgb.astype(np.uint8)
        return Image.fromarray(arr)
    
    @staticmethod
    def convert_for_gif(img: Image.Image) -> Image.Image:
        if img.mode != "RGBA":
            img = img.convert("RGBA")
        
        alpha = img.getchannel("A")
        mask = Image.eval(alpha, lambda a: 255 if a > 10 else 0)
        
        bg = Image.new("RGB", img.size, (0, 0, 0))
        bg.paste(img, mask=img.split()[3])
        
        p_img = bg.convert("P", palette=Image.ADAPTIVE, colors=255)
        
        new_img = Image.new("RGBA", img.size)
        new_img.paste(img, (0,0), mask=mask)
        return new_img

class JSONEncoder(json.JSONEncoder):
    def default(self, o: Any) -> Any:
        if dataclasses.is_dataclass(o):
            return dataclasses.asdict(o)
        if isinstance(o, (IntEnum, IntFlag)):
            return f"{o.name} ({o.value})"
        if isinstance(o, bytes):
            return f"<Bytes length={len(o)}>"
        return super().default(o)

def process_file_cli(file_path: str, info_only: bool, fix_additive: bool, export_sequence: bool, force_gif: bool, export_all: bool):
    try:
        print(f"正在处理: {file_path}")
        tex = TexParser.parse(file_path)
        
        if info_only:
            info_data = {
                "filename": os.path.basename(file_path),
                "header": tex.header,
                "container_version": tex.image_container.version,
                "container_magic": tex.image_container.magic,
                "image_format": tex.image_container.image_format,
                "frames_count": len(tex.frame_info_container.frames) if tex.frame_info_container else 0,
                "images_count": len(tex.image_container.images)
            }
            if TexFlags.IsVideoTexture in tex.header.flags:
                info_data["type"] = "VideoTexture"
            elif TexFlags.IsGif in tex.header.flags:
                info_data["type"] = "GIF/Animated"
            else:
                info_data["type"] = "Static"

            print(json.dumps(info_data, cls=JSONEncoder, indent=4, ensure_ascii=False))
            return

        output_dir = os.path.dirname(file_path)
        base_name = os.path.splitext(os.path.basename(file_path))[0]
        
        if TexFlags.IsVideoTexture in tex.header.flags:
            try:
                img = tex.image_container.images[0]
                mip = img.mipmaps[0]
                ext = "mp4"
                out_path = os.path.join(output_dir, f"{base_name}.{ext}")
                with open(out_path, 'wb') as f:
                    f.write(mip.bytes_data)
                print(f"  [成功] 视频导出至: {out_path}")
            except Exception as e:
                print(f"  [错误] 视频导出失败: {e}")
            return

        # 使用新的接口同时获取图像和时间
        images, durations = TexConverter.to_image_and_duration(tex, apply_fix_additive=fix_additive)
        
        if not images:
            print("  [警告] 无图像数据 (可能所有帧均为空白)")
            return

        if export_sequence:
            seq_dir = os.path.join(output_dir, f"{base_name}_seq")
            if not os.path.exists(seq_dir):
                os.makedirs(seq_dir)
            print(f"  [信息] 导出序列帧至: {seq_dir}")
            for idx, img in enumerate(images):
                img.save(os.path.join(seq_dir, f"{idx:04d}.png"), "PNG")
            print(f"  [成功] 序列帧导出完成。")
            return

        if TexFlags.IsGif in tex.header.flags and len(images) > 1:
            do_webp = True
            do_gif = False

            if force_gif:
                do_webp = False
                do_gif = True
            
            if export_all:
                do_webp = True
                do_gif = True

            if do_webp:
                webp_path = os.path.join(output_dir, f"{base_name}.webp")
                images[0].save(
                    webp_path,
                    save_all=True,
                    append_images=images[1:],
                    duration=durations,
                    loop=0,
                    lossless=True,
                    quality=100,
                    method=6
                )
                print(f"  [成功] WebP 动画导出至: {webp_path}")

            if do_gif:
                gif_path = os.path.join(output_dir, f"{base_name}.gif")
                gif_frames = []
                for img in images:
                    if fix_additive:
                        # GIF 转换时需要确保已经是修复过的
                        gif_frames.append(TexConverter.convert_for_gif(img if fix_additive else TexConverter.apply_additive_fix(img)))
                    else:
                        gif_frames.append(TexConverter.convert_for_gif(img))
                
                gif_frames[0].save(
                    gif_path,
                    save_all=True,
                    append_images=gif_frames[1:],
                    duration=durations,
                    loop=0,
                    disposal=2,
                    transparency=0
                )
                print(f"  [成功] GIF 动画导出至: {gif_path}")
        else:
            out_path = os.path.join(output_dir, f"{base_name}.png")
            images[0].save(out_path)
            print(f"  [成功] 图像导出至: {out_path}")

    except Exception as e:
        print(f"  [失败] 无法处理 {file_path}: {e}")

def cli_main():
    parser = argparse.ArgumentParser(description="SceneTexParser - Wallpaper Engine .tex 解析与导出工具")
    parser.add_argument("input", help=".tex 文件或包含 .tex 文件的文件夹")
    parser.add_argument("-r", "--recursive", action="store_true", help="递归搜索子文件夹 (仅当输入为文件夹时有效)")
    parser.add_argument("-i", "--info", action="store_true", help="仅输出详情 JSON 信息，不导出图像")
    parser.add_argument("-f", "--fix-additive", action="store_true", help="应用 Additive 混合修复 (去除黑色背景)")
    parser.add_argument("-s", "--sequence", action="store_true", help="将动画导出为 PNG 序列帧文件夹")
    parser.add_argument("-g", "--gif", action="store_true", help="强制仅导出 GIF 格式 (默认导出 WebP)")
    parser.add_argument("-a", "--all", action="store_true", help="同时导出 WebP 和 GIF 格式")
    
    args = parser.parse_args()
    
    targets = []
    
    if os.path.isfile(args.input):
        targets.append(args.input)
    elif os.path.isdir(args.input):
        if args.recursive:
            for root, dirs, files in os.walk(args.input):
                for file in files:
                    if file.lower().endswith(".tex"):
                        targets.append(os.path.join(root, file))
        else:
            for file in os.listdir(args.input):
                if file.lower().endswith(".tex"):
                    targets.append(os.path.join(args.input, file))
    else:
        print(f"错误: 输入路径不存在: {args.input}")
        return

    if not targets:
        print("未找到 .tex 文件。")
        return

    print(f"找到 {len(targets)} 个文件，开始处理...")
    
    for path in targets:
        process_file_cli(path, args.info, args.fix_additive, args.sequence, args.gif, args.all)
    
    if not args.info:
        print(f"\n所有任务完成。")

class ImageViewer(QWidget):
    def __init__(self):
        super().__init__()
        self.layout = QVBoxLayout(self)
        self.layout.setContentsMargins(0, 0, 0, 0)
        
        self.label = QLabel("请拖入 .tex 文件")
        self.label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.label.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Ignored)
        
        self.layout.addWidget(self.label)
        self.frames: List[QImage] = []
        self.durations: List[int] = []
        self.current_frame = 0
        self.timer = QTimer()
        self.timer.setSingleShot(True)
        self.timer.timeout.connect(self.next_frame)

    def load_images(self, pil_images: List[Image.Image], durations: List[int]):
        self.timer.stop()
        self.frames = []
        self.durations = durations
        
        if not self.durations:
             self.durations = [100] * len(pil_images)

        for pimg in pil_images:
            if pimg.mode != 'RGBA':
                pimg = pimg.convert('RGBA')
            data = pimg.tobytes("raw", "RGBA")
            qimg = QImage(data, pimg.width, pimg.height, QImage.Format.Format_RGBA8888)
            self.frames.append(qimg)
        
        if self.frames:
            self.current_frame = 0
            self.show_frame()
            if len(self.frames) > 1:
                self.schedule_next()
        else:
            self.label.setText("无法显示图像 / 视频纹理")

    def show_frame(self):
        if not self.frames: return
        pix = QPixmap.fromImage(self.frames[self.current_frame])
        
        size = self.size()
        if size.width() <= 1 or size.height() <= 1:
            return

        scaled = pix.scaled(size, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
        self.label.setPixmap(scaled)

    def schedule_next(self):
        if not self.durations: return
        delay = self.durations[self.current_frame]
        self.timer.start(int(max(10, delay)))

    def next_frame(self):
        self.current_frame = (self.current_frame + 1) % len(self.frames)
        self.show_frame()
        self.schedule_next()

    def resizeEvent(self, event):
        self.show_frame()
        super().resizeEvent(event)

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("SceneTexParser - Final Fix")
        self.resize(1000, 700)
        self.setAcceptDrops(True)

        central = QWidget()
        self.setCentralWidget(central)
        layout = QHBoxLayout(central)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        layout.addWidget(splitter)

        self.info_text = QTextEdit()
        self.info_text.setReadOnly(True)
        self.info_text.setPlaceholderText("文件信息将显示在这里...")
        splitter.addWidget(self.info_text)

        self.viewer = ImageViewer()
        self.viewer_container = QFrame()
        self.viewer_container.setLayout(QVBoxLayout())
        self.viewer_container.layout().setContentsMargins(0,0,0,0)
        self.viewer_container.layout().addWidget(self.viewer)
        self.viewer_container.setStyleSheet("background-color: #333;")
        splitter.addWidget(self.viewer_container)

        splitter.setSizes([300, 700])
        
        toolbar = self.addToolBar("工具")
        
        btn_save = QAction("导出图片 / 视频", self)
        btn_save.triggered.connect(self.export_images)
        toolbar.addAction(btn_save)
        
        toolbar.addSeparator()

        self.chk_fix_additive = QCheckBox("修复黑色背景 (Additive)")
        self.chk_fix_additive.setToolTip("将黑色背景转换为透明 (适用于 Additive 混合模式的纹理)")
        self.chk_fix_additive.stateChanged.connect(self.refresh_display)
        toolbar.addWidget(self.chk_fix_additive)
        
        self.current_tex: Optional[TexFile] = None
        self.original_pil_images: List[Image.Image] = []
        self.display_pil_images: List[Image.Image] = []
        self.original_durations: List[int] = []

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.accept()
        else:
            event.ignore()

    def dropEvent(self, event: QDropEvent):
        files = [u.toLocalFile() for u in event.mimeData().urls()]
        for f in files:
            if f.lower().endswith('.tex'):
                self.load_tex(f)
                break

    def load_tex(self, path):
        try:
            tex = TexParser.parse(path)
            self.current_tex = tex
            
            info = f"文件: {os.path.basename(path)}\n"
            info += f"尺寸: {tex.header.texture_width}x{tex.header.texture_height}\n"
            info += f"格式: {tex.header.format.name}\n"
            info += f"标志 (Flags): {str(tex.header.flags)}\n"
            info += f"容器: {tex.image_container.magic} (V{tex.image_container.version.value})\n"
            
            if tex.frame_info_container:
                info += f"\nGIF 动画信息:\n帧数: {len(tex.frame_info_container.frames)}\n"
                info += f"画布尺寸: {tex.frame_info_container.gif_width}x{tex.frame_info_container.gif_height}\n"
            
            if TexFlags.IsVideoTexture in tex.header.flags:
                info += "\n[检测到视频纹理]\n预览暂不支持。\n请点击工具栏的“导出”按钮提取 .mp4 文件。"
            
            self.info_text.setText(info)

            # 一次性解析图像和时间
            self.original_pil_images, self.original_durations = TexConverter.to_image_and_duration(tex)
            self.refresh_display()

        except Exception as e:
            QMessageBox.critical(self, "错误", f"解析失败:\n{str(e)}")
            self.info_text.setText(f"发生错误:\n{e}")

    def refresh_display(self):
        if not self.original_pil_images:
            return

        fix_additive = self.chk_fix_additive.isChecked()
        
        processed_images = []
        for img in self.original_pil_images:
            if fix_additive:
                processed_images.append(TexConverter.apply_additive_fix(img))
            else:
                processed_images.append(img.copy())
        
        self.display_pil_images = processed_images
        self.viewer.load_images(self.display_pil_images, self.original_durations)

    def export_images(self):
        if not self.current_tex: return
        
        if TexFlags.IsVideoTexture in self.current_tex.header.flags:
            try:
                img = self.current_tex.image_container.images[0]
                mip = img.mipmaps[0]
                header_sig = mip.bytes_data[4:8]
                if header_sig in [b'ftyp', b'msnv', b'mp42', b'isom']:
                    path, _ = QFileDialog.getSaveFileName(self, "保存视频", "texture.mp4", "Video (*.mp4)")
                    if path:
                        with open(path, 'wb') as f:
                            f.write(mip.bytes_data)
                        QMessageBox.information(self, "成功", "视频已成功导出。")
                else:
                    QMessageBox.warning(self, "警告", "未检测到有效的 MP4 头，无法直接导出。")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"导出视频失败: {e}")
            return

        if not self.display_pil_images:
            QMessageBox.warning(self, "提示", "没有可导出的图像。")
            return
        
        default_name = "texture.webp"
        filters = "WebP 动画 (*.webp);;GIF 动画 (*.gif);;PNG 图像 (*.png)"
        
        path, _ = QFileDialog.getSaveFileName(self, "保存图片", default_name, filters)
        if not path: return

        try:
            is_anim = TexFlags.IsGif in self.current_tex.header.flags and len(self.display_pil_images) > 1
            
            # 使用已解析好的 durations
            durations = self.original_durations if self.original_durations else [100]*len(self.display_pil_images)

            if path.lower().endswith('.webp'):
                if is_anim:
                    self.display_pil_images[0].save(
                        path,
                        save_all=True,
                        append_images=self.display_pil_images[1:],
                        duration=durations,
                        loop=0,
                        lossless=True,
                        quality=100,
                        method=6
                    )
                else:
                    self.display_pil_images[0].save(path, lossless=True, quality=100, method=6)

            elif path.lower().endswith('.gif'):
                if is_anim:
                    frames_to_save = [TexConverter.convert_for_gif(img) for img in self.display_pil_images]
                    frames_to_save[0].save(
                        path,
                        save_all=True,
                        append_images=frames_to_save[1:],
                        duration=durations,
                        loop=0,
                        disposal=2,
                        transparency=0
                    )
                else:
                    TexConverter.convert_for_gif(self.display_pil_images[0]).save(path)

            else:
                self.display_pil_images[0].save(path)

            QMessageBox.information(self, "成功", "导出成功。")
        except Exception as e:
            QMessageBox.critical(self, "错误", f"保存失败: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cli_main()
    else:
        if not GUI_AVAILABLE:
            print("PyQt6 库未安装，且未检测到命令行参数。\n请使用 'pip install PyQt6' 或使用命令行参数运行。")
            sys.exit(1)
            
        app = QApplication(sys.argv)
        window = MainWindow()
        window.show()
        sys.exit(app.exec())