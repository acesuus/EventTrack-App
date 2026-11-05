"""Export the approved Campus Pin artwork to platform icon sizes."""
from pathlib import Path
import json
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / 'assets/branding/campus_pin.png').convert('RGBA')
bounds = source.getchannel('A').point(lambda value: 255 if value > 32 else 0).getbbox()
mark = source.crop(bounds)
mark.save(ROOT / 'assets/branding/campus_pin_mark.png')

def export(path, size, fraction=0.72, transparent=False):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas = Image.new('RGBA', (size, size), (255, 255, 255, 0 if transparent else 255))
    symbol = ImageOps.contain(mark, (round(size*fraction), round(size*fraction)), Image.Resampling.LANCZOS)
    canvas.alpha_composite(symbol, ((size-symbol.width)//2, (size-symbol.height)//2))
    (canvas if transparent else canvas.convert('RGB')).save(path)

res = Path('android/app/src/main/res')
for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
    export(res / f'mipmap-{density}/ic_launcher.png', size)
    export(res / f'drawable-{density}/eventtrack_splash.png', round(size / 48 * 96), transparent=True)
export(res / 'drawable-nodpi/eventtrack_foreground.png', 432, 0.60, transparent=True)
adaptive = ROOT / res / 'mipmap-anydpi-v26/ic_launcher.xml'
adaptive.parent.mkdir(parents=True, exist_ok=True)
adaptive.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/white" />
    <foreground android:drawable="@drawable/eventtrack_foreground" />
</adaptive-icon>
''', encoding='utf-8')
for folder in ['drawable', 'drawable-v21']:
    (ROOT / res / folder / 'launch_background.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white" />
    <item><bitmap android:gravity="center" android:src="@drawable/eventtrack_splash" /></item>
</layer-list>
''', encoding='utf-8')

for folder in ['ios/Runner/Assets.xcassets/AppIcon.appiconset', 'macos/Runner/Assets.xcassets/AppIcon.appiconset']:
    contents = ROOT / folder / 'Contents.json'
    if not contents.exists():
        continue
    for item in json.loads(contents.read_text())['images']:
        if item.get('filename'):
            size = round(float(item['size'].split('x')[0]) * float(item.get('scale', '1x').rstrip('x')))
            export(Path(folder) / item['filename'], size)
for scale in [1, 2, 3]:
    suffix = '' if scale == 1 else f'@{scale}x'
    export(f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', 96*scale, transparent=True)
for size in [192, 512]:
    export(f'web/icons/Icon-{size}.png', size)
    export(f'web/icons/Icon-maskable-{size}.png', size, 0.60)
export('web/favicon.png', 32)
windows = ROOT / 'windows/runner/resources/app_icon.ico'
if windows.parent.exists():
    icon = Image.new('RGBA', (256,256), 'white')
    symbol = ImageOps.contain(mark, (184,184), Image.Resampling.LANCZOS)
    icon.alpha_composite(symbol, ((256-symbol.width)//2, (256-symbol.height)//2))
    icon.save(windows, sizes=[(n,n) for n in [16,24,32,48,64,128,256]])
manifest = ROOT / 'web/manifest.json'
data = json.loads(manifest.read_text())
data.update(name='EventTrack', short_name='EventTrack', background_color='#EAF9F1', theme_color='#28A776', description='Campus event attendance and location verification.')
manifest.write_text(json.dumps(data, indent=4)+'\n', encoding='utf-8')
print('Exported Campus Pin branding for app assets, Android, iOS, macOS, web, and Windows where configured.')
