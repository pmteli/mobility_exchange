"""Decode only JPEG/PNG, orient, resize and re-encode pixels without metadata."""
import sys, warnings, resource
from PIL import Image, ImageOps
resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
resource.setrlimit(resource.RLIMIT_AS, (768 * 1024**2, 768 * 1024**2))
Image.MAX_IMAGE_PIXELS = 25_000_000
warnings.simplefilter('error', Image.DecompressionBombWarning)
try:
    with Image.open(sys.argv[1], formats=['JPEG', 'PNG']) as source:
        if source.width * source.height > Image.MAX_IMAGE_PIXELS or getattr(source, 'n_frames', 1) != 1:
            raise ValueError('Image is too large or animated')
        source.load()
        oriented = ImageOps.exif_transpose(source).convert('RGB')
        oriented.thumbnail((2400, 2400))
        clean = Image.new('RGB', oriented.size)
        clean.paste(oriented)
        clean.save(sys.argv[2], format='JPEG', quality=88, optimize=True)
except Exception:
    sys.exit(1)
