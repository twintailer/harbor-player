"""Package the existing Kairo iPhone icon into Apple's layered TV asset format."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'TVAssets.xcassets'
BRAND = CATALOG / 'App Icon & Top Shelf Image.brandassets'
INFO = {'author': 'xcode', 'version': 1}


def manifest(folder, data):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'Contents.json').write_text(json.dumps({**data, 'info': INFO}, indent=2), encoding='utf-8')


source = Image.open(ROOT / 'Assets.xcassets/AppIcon.appiconset/Icon.png').convert('RGBA')
manifest(CATALOG, {})
manifest(BRAND, {'assets': [
    {'filename': 'App Icon.imagestack', 'idiom': 'tv', 'role': 'primary-app-icon', 'size': '400x240'},
    {'filename': 'App Store.imagestack', 'idiom': 'tv', 'role': 'primary-app-icon', 'size': '1280x768'},
    {'filename': 'Top Shelf.imageset', 'idiom': 'tv', 'role': 'top-shelf-image', 'size': '1920x720'},
    {'filename': 'Top Shelf Wide.imageset', 'idiom': 'tv', 'role': 'top-shelf-image-wide', 'size': '2320x720'},
]})
for name, width, height, scales in [('App Icon', 400, 240, [1, 2]), ('App Store', 1280, 768, [1])]:
    stack = BRAND / (name + '.imagestack')
    # Asset catalogs list the frontmost layer first; the last layer must be opaque.
    manifest(stack, {'layers': [{'filename': 'Front.imagestacklayer'}, {'filename': 'Back.imagestacklayer'}]})
    for layer in ['Back', 'Front']:
        folder = stack / (layer + '.imagestacklayer')
        manifest(folder, {})
        content = folder / 'Content.imageset'
        manifest(content, {'images': [{'idiom': 'tv', 'filename': f'icon_{scale}x.png', 'scale': f'{scale}x'} for scale in scales]})
        for scale in scales:
            canvas = Image.new('RGBA', (width * scale, height * scale), (8, 14, 20, 255) if layer == 'Back' else (0, 0, 0, 0))
            if layer == 'Front':
                side = int(height * scale * 0.8)
                icon = source.resize((side, side), Image.Resampling.LANCZOS)
                canvas.alpha_composite(icon, ((width * scale - side) // 2, (height * scale - side) // 2))
            canvas.save(content / f'icon_{scale}x.png')
for name, width in [('Top Shelf', 1920), ('Top Shelf Wide', 2320)]:
    folder = BRAND / (name + '.imageset')
    manifest(folder, {'images': [{'idiom': 'tv', 'filename': 'shelf.png', 'scale': '1x'}]})
    canvas = Image.new('RGBA', (width, 720), (8, 14, 20, 255))
    icon = source.resize((576, 576), Image.Resampling.LANCZOS)
    canvas.alpha_composite(icon, ((width - 576) // 2, 72))
    canvas.convert('RGB').save(folder / 'shelf.png')
print('Apple TV icon and Top Shelf assets generated')
