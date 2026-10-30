"""Preserve document detail while producing a metadata-free Textract image."""
import io
import resource
import sys
import warnings
from PIL import Image, ImageOps

resource.setrlimit(resource.RLIMIT_CPU, (30, 30))
resource.setrlimit(resource.RLIMIT_AS, (1536 * 1024**2, 1536 * 1024**2))
Image.MAX_IMAGE_PIXELS = 50_000_000
warnings.simplefilter('error', Image.DecompressionBombWarning)
MAX_BYTES = 10_000_000
try:
    with open(sys.argv[1], 'rb') as probe:
        is_pdf = probe.read(1024).lstrip().startswith(b'%PDF-')
    if is_pdf:
        import fitz
        with fitz.open(sys.argv[1]) as document:
            if document.needs_pass or document.is_encrypted:
                sys.exit(3)
            if document.page_count != 1:
                sys.exit(2)
            page = document[0]
            scale = min(300 / 72, 10000 / max(page.rect.width, page.rect.height))
            if page.rect.width * page.rect.height * scale * scale > Image.MAX_IMAGE_PIXELS:
                scale = (Image.MAX_IMAGE_PIXELS / (page.rect.width * page.rect.height)) ** .5
            pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), colorspace=fitz.csRGB, alpha=False)
            image_source = io.BytesIO(pix.tobytes('png'))
    else:
        image_source = sys.argv[1]
    with Image.open(image_source, formats=['JPEG', 'PNG']) as source:
        if source.width * source.height > Image.MAX_IMAGE_PIXELS or getattr(source, 'n_frames', 1) != 1:
            raise ValueError('Image is too large or animated')
        source.load()
        oriented = ImageOps.exif_transpose(source).convert('RGB')
        oriented.thumbnail((10000, 10000), Image.Resampling.LANCZOS)
        clean = Image.new('RGB', oriented.size, 'white')
        clean.paste(oriented)
        # Prefer full resolution; reduce dimensions only when compression cannot
        # meet the service limit. No source metadata is copied to the output.
        while True:
            for quality in (95, 90, 85):
                output = io.BytesIO()
                clean.save(output, format='JPEG', quality=quality, subsampling=0)
                if output.tell() <= MAX_BYTES:
                    with open(sys.argv[2], 'wb') as target:
                        target.write(output.getvalue())
                    sys.exit(0)
            clean = clean.resize((max(1, int(clean.width * .85)), max(1, int(clean.height * .85))), Image.Resampling.LANCZOS)
except Exception:
    sys.exit(1)
