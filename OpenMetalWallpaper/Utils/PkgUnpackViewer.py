import sys
import os
import struct
import json
import argparse
from pathlib import Path

class PkgEntry:
    def __init__(self, path, offset, length):
        self.path = path.replace('\\', '/')
        self.offset = offset
        self.length = length
        self.name = self.path.split('/')[-1]
        self.extension = Path(self.path).suffix.lower()

class PkgReader:
    def __init__(self, filepath):
        self.filepath = Path(filepath)
        self.entries = []
        self.magic = ""
        self.data_start_offset = 0
        self._parse()

    def _read_string(self, f):
        length_bytes = f.read(4)
        if not length_bytes:
            return None
        length = struct.unpack('<i', length_bytes)[0]
        if length < 0 or length > 4096:
            raise ValueError(f"字符串长度异常: {length}")
        string_bytes = f.read(length)
        return string_bytes.decode('utf-8', errors='replace')

    def _parse(self):
        try:
            with open(self.filepath, 'rb') as f:
                self.magic = self._read_string(f)
                
                entry_count_bytes = f.read(4)
                if not entry_count_bytes:
                    raise ValueError("无法读取条目数量")
                entry_count = struct.unpack('<i', entry_count_bytes)[0]

                for _ in range(entry_count):
                    path = self._read_string(f)
                    offset = struct.unpack('<i', f.read(4))[0]
                    length = struct.unpack('<i', f.read(4))[0]
                    self.entries.append(PkgEntry(path, offset, length))
                
                self.data_start_offset = f.tell()
        except Exception as e:
            raise RuntimeError(f"解析PKG文件失败: {str(e)}")

    def extract_file(self, entry, output_dir):
        try:
            full_output_path = output_dir / entry.path
            full_output_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(self.filepath, 'rb') as src, open(full_output_path, 'wb') as dst:
                src.seek(self.data_start_offset + entry.offset)
                data = src.read(entry.length)
                dst.write(data)
            return True
        except Exception:
            return False

    def dump_info(self):
        return {
            "magic": self.magic,
            "entry_count": len(self.entries),
            "files": [
                {"path": e.path, "offset": e.offset, "length": e.length}
                for e in self.entries
            ]
        }

try:
    from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                                 QHBoxLayout, QTreeWidget, QTreeWidgetItem, QSplitter,
                                 QTextEdit, QFileDialog, QLabel, QToolBar, QMessageBox,
                                 QMenu, QStyle, QProgressBar, QHeaderView)
    from PyQt6.QtCore import Qt, QSize
    from PyQt6.QtGui import QAction, QIcon, QDragEnterEvent, QDropEvent
except ImportError:
    pass

class PkgViewerWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("PkgUnpackViewer")
        self.resize(1000, 700)
        self.setAcceptDrops(True)
        self.pkg_reader = None
        self.tree_nodes = {}
        self.init_ui()

    def init_ui(self):
        toolbar = QToolBar("Main Toolbar")
        toolbar.setMovable(False)
        self.addToolBar(toolbar)

        style = self.style()
        icon_open = style.standardIcon(QStyle.StandardPixmap.SP_DialogOpenButton)
        icon_save = style.standardIcon(QStyle.StandardPixmap.SP_DialogSaveButton)

        action_open = QAction(icon_open, "打开文件", self)
        action_open.triggered.connect(self.open_file_dialog)
        toolbar.addAction(action_open)

        action_extract_all = QAction(icon_save, "全部导出", self)
        action_extract_all.triggered.connect(self.export_all)
        toolbar.addAction(action_extract_all)
        
        self.status_label = QLabel("就绪")
        self.statusBar().addWidget(self.status_label)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        self.setCentralWidget(splitter)

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["文件名", "大小", "类型"])
        self.tree.setColumnWidth(0, 400)
        self.tree.setAlternatingRowColors(False)
        self.tree.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.tree.customContextMenuRequested.connect(self.open_context_menu)
        self.tree.setSelectionMode(QTreeWidget.SelectionMode.ExtendedSelection)
        splitter.addWidget(self.tree)

        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        right_layout.addWidget(self.log_text)
        
        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        right_layout.addWidget(self.progress_bar)

        splitter.addWidget(right_widget)
        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 1)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.accept()
        else:
            event.ignore()

    def dropEvent(self, event: QDropEvent):
        files = [u.toLocalFile() for u in event.mimeData().urls()]
        if files and files[0].lower().endswith('.pkg'):
            self.load_file(files[0])

    def log(self, msg):
        self.log_text.append(f">> {msg}")
        sb = self.log_text.verticalScrollBar()
        sb.setValue(sb.maximum())
        self.status_label.setText(msg)
        QApplication.processEvents()

    def format_size(self, size):
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024:
                return f"{size:.2f} {unit}"
            size /= 1024
        return f"{size:.2f} TB"

    def open_file_dialog(self):
        fname, _ = QFileDialog.getOpenFileName(self, '打开 .pkg 文件', '', 'PKG Files (*.pkg);;All Files (*)')
        if fname:
            self.load_file(fname)

    def load_file(self, path):
        try:
            self.pkg_reader = PkgReader(path)
            self.setWindowTitle(f"PkgUnpackViewer - {Path(path).name}")
            self.log(f"已加载: {path}")
            self.log(f"Magic: {self.pkg_reader.magic}, 条目数: {len(self.pkg_reader.entries)}")
            self.populate_tree()
        except Exception as e:
            QMessageBox.critical(self, "错误", f"无法打开文件:\n{str(e)}")
            self.log(f"错误: {str(e)}")

    def populate_tree(self):
        self.tree.clear()
        self.tree_nodes = {}
        style = self.style()
        icon_folder = style.standardIcon(QStyle.StandardPixmap.SP_DirIcon)
        icon_file = style.standardIcon(QStyle.StandardPixmap.SP_FileIcon)

        root_item = QTreeWidgetItem(self.tree)
        root_item.setText(0, "/")
        root_item.setText(2, "根目录")
        root_item.setIcon(0, icon_folder)
        root_item.setExpanded(True)
        self.tree_nodes[""] = root_item
        root_item.setData(0, Qt.ItemDataRole.UserRole, {"type": "folder", "path": ""})

        for index, entry in enumerate(self.pkg_reader.entries):
            parts = entry.path.split('/')
            current_path = ""
            parent_item = root_item

            for i, part in enumerate(parts):
                is_file = (i == len(parts) - 1)
                
                if current_path:
                    current_path += "/" + part
                else:
                    current_path = part
                
                if current_path not in self.tree_nodes:
                    item = QTreeWidgetItem(parent_item)
                    item.setText(0, part)
                    
                    if is_file:
                        item.setText(1, self.format_size(entry.length))
                        item.setText(2, entry.extension)
                        item.setIcon(0, icon_file)
                        item.setData(0, Qt.ItemDataRole.UserRole, {"type": "file", "index": index})
                    else:
                        item.setText(2, "文件夹")
                        item.setIcon(0, icon_folder)
                        item.setData(0, Qt.ItemDataRole.UserRole, {"type": "folder", "path": current_path})
                    
                    self.tree_nodes[current_path] = item
                
                parent_item = self.tree_nodes[current_path]

    def open_context_menu(self, position):
        items = self.tree.selectedItems()
        if not items:
            return

        menu = QMenu()
        first_item = items[0]
        data = first_item.data(0, Qt.ItemDataRole.UserRole)
        
        if not data: return

        if data["type"] == "file":
            action = QAction("导出文件", self)
            action.triggered.connect(lambda: self.export_selected_file(data["index"]))
            menu.addAction(action)
        elif data["type"] == "folder":
            action = QAction("导出文件夹 (递归)", self)
            action.triggered.connect(lambda: self.export_selected_folder(first_item))
            menu.addAction(action)

        menu.exec(self.tree.viewport().mapToGlobal(position))

    def export_selected_file(self, index):
        if not self.pkg_reader: return
        entry = self.pkg_reader.entries[index]
        
        default_name = entry.name
        file_path, _ = QFileDialog.getSaveFileName(self, "保存文件", default_name)
        
        if file_path:
            try:
                with open(self.pkg_reader.filepath, 'rb') as src, open(file_path, 'wb') as dst:
                    src.seek(self.pkg_reader.data_start_offset + entry.offset)
                    dst.write(src.read(entry.length))
                self.log(f"已导出: {file_path}")
                QMessageBox.information(self, "成功", "文件导出成功！")
            except Exception as e:
                QMessageBox.critical(self, "错误", str(e))

    def export_selected_folder(self, folder_item):
        dir_path = QFileDialog.getExistingDirectory(self, "选择导出目录")
        if not dir_path: return

        self.log(f"开始导出文件夹: {folder_item.text(0)}")
        count = self._recursive_export_tree_item(folder_item, Path(dir_path))
        self.log(f"导出完成，共 {count} 个文件")
        QMessageBox.information(self, "完成", f"成功导出 {count} 个文件")

    def _recursive_export_tree_item(self, parent_item, target_base_path):
        count = 0
        for i in range(parent_item.childCount()):
            child = parent_item.child(i)
            data = child.data(0, Qt.ItemDataRole.UserRole)
            
            if data["type"] == "file":
                entry = self.pkg_reader.entries[data["index"]]
                if self.pkg_reader.extract_file(entry, target_base_path):
                    self.log(f"导出: {entry.path}")
                    count += 1
            elif data["type"] == "folder":
                count += self._recursive_export_tree_item(child, target_base_path)
        return count

    def export_all(self):
        if not self.pkg_reader:
            QMessageBox.warning(self, "警告", "请先打开一个 .pkg 文件")
            return

        dir_path = QFileDialog.getExistingDirectory(self, "选择全部导出的根目录")
        if not dir_path: return

        total = len(self.pkg_reader.entries)
        self.progress_bar.setMaximum(total)
        self.progress_bar.setValue(0)
        self.progress_bar.setVisible(True)
        self.tree.setEnabled(False)

        count = 0
        try:
            for i, entry in enumerate(self.pkg_reader.entries):
                if self.pkg_reader.extract_file(entry, Path(dir_path)):
                    count += 1
                
                if i % 10 == 0:
                    self.progress_bar.setValue(i + 1)
                    QApplication.processEvents()
            
            self.progress_bar.setValue(total)
            self.log(f"全部导出完成: {count}/{total}")
            QMessageBox.information(self, "完成", f"已导出 {count} 个文件")
        except Exception as e:
            QMessageBox.critical(self, "错误", f"导出过程中出错: {str(e)}")
        finally:
            self.progress_bar.setVisible(False)
            self.tree.setEnabled(True)

def cli_main():
    parser = argparse.ArgumentParser(description="PkgUnpackViewer - .pkg 解析工具")
    parser.add_argument("input", help=".pkg文件路径或包含单个.pkg文件的文件夹")
    parser.add_argument("-i", "--info", action="store_true", help="输出详情信息到.json但不解包")
    parser.add_argument("-o", "--output", help="输出目录（默认为.pkg文件同目录）")
    
    args = parser.parse_args()
    
    input_path = Path(args.input).resolve()
    pkg_file = None

    if input_path.is_file():
        if input_path.suffix.lower() == '.pkg':
            pkg_file = input_path
        else:
            print("错误: 输入文件不是 .pkg 格式")
            sys.exit(1)
    elif input_path.is_dir():
        pkg_files = list(input_path.glob("*.pkg"))
        if len(pkg_files) == 0:
            print("错误: 文件夹中未找到 .pkg 文件")
            sys.exit(1)
        elif len(pkg_files) > 1:
            print(f"错误: 文件夹中包含多个 .pkg 文件: {[f.name for f in pkg_files]}")
            sys.exit(1)
        else:
            pkg_file = pkg_files[0]
    else:
        print("错误: 输入路径不存在")
        sys.exit(1)

    print(f"正在处理: {pkg_file}")
    
    try:
        reader = PkgReader(pkg_file)
    except Exception as e:
        print(f"解析失败: {e}")
        sys.exit(1)

    if args.info:
        json_path = pkg_file.with_suffix('.json')
        if args.output:
            out_p = Path(args.output)
            if out_p.is_dir() or (not out_p.exists() and not out_p.suffix):
                 out_p.mkdir(parents=True, exist_ok=True)
                 json_path = out_p / f"{pkg_file.stem}.json"
            else:
                 json_path = out_p

        info = reader.dump_info()
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(info, f, indent=4, ensure_ascii=False)
        print(f"详情已导出至: {json_path}")
    else:
        output_dir = pkg_file.parent
        if args.output:
            output_dir = Path(args.output)
        
        print(f"正在解包到: {output_dir}")
        if not output_dir.exists():
            try:
                output_dir.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                print(f"无法创建输出目录: {e}")
                output_dir = pkg_file.parent
                print(f"回退到默认目录: {output_dir}")

        success_count = 0
        total = len(reader.entries)
        for i, entry in enumerate(reader.entries):
            if i % 50 == 0:
                print(f"进度: {i}/{total}...")
            if reader.extract_file(entry, output_dir):
                success_count += 1
            else:
                print(f"提取失败: {entry.path}")
        
        if pkg_file.parent != output_dir:
            try:
                project_json_src = pkg_file.parent / "project.json"
                if project_json_src.exists():
                    project_json_dst = output_dir / "project.json"
                    with open(project_json_src, 'r', encoding='utf-8') as src_f:
                        project_data = json.load(src_f)
                    if "preview" in project_data:
                        preview_name = project_data["preview"]
                        preview_src = pkg_file.parent / preview_name
                        if preview_src.exists():
                            import shutil
                            shutil.copy2(project_json_src, project_json_dst)
                            preview_dst = output_dir / preview_name
                            shutil.copy2(preview_src, preview_dst)
                            print(f"已复制 project.json 和 {preview_name} 到输出目录")
                    else:
                        import shutil
                        shutil.copy2(project_json_src, project_json_dst)
                        print("已复制 project.json 到输出目录")
                else:
                    print("未找到 project.json")
            except Exception as e:
                print(f"复制额外文件时出错: {e}")

        print(f"完成。成功提取 {success_count}/{total} 个文件。")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cli_main()
    else:
        try:
            from PyQt6.QtWidgets import QApplication
        except ImportError:
            print("错误: 未检测到 PyQt6。请运行 `pip3 install PyQt6` 安装。")
            sys.exit(1)

        app = QApplication(sys.argv)
        app.setStyle("Fusion")
        window = PkgViewerWindow()
        window.show()
        sys.exit(app.exec())