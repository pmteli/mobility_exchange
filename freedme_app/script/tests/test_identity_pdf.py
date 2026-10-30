import subprocess
import tempfile
import unittest
from pathlib import Path
import fitz
from PIL import Image

class IdentityPdfTest(unittest.TestCase):
    def test_pdf_validation_and_rendering(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'document.pdf'
            output = Path(folder) / 'render.jpg'
            doc = fitz.open()
            page = doc.new_page()
            page.insert_text((72, 72), 'Fictional test document: Maya Patel, 123 Example Street, Fremont CA 94536')
            doc.save(source)
            command = ['python3', 'script/sanitize_identity_document.py', str(source), str(output)]
            self.assertEqual(0, subprocess.run(command).returncode)
            with Image.open(output) as image:
                self.assertGreater(image.width, 2400)
                self.assertFalse(image.getexif())
            self.assertLessEqual(output.stat().st_size, 10_000_000)
            source.unlink()
            doc.new_page()
            doc.save(source)
            self.assertEqual(2, subprocess.run(command).returncode)
            source.unlink()
            doc.save(source, encryption=fitz.PDF_ENCRYPT_AES_256, owner_pw='owner', user_pw='password')
            self.assertEqual(3, subprocess.run(command).returncode)
            source.write_bytes(b'%PDF-invalid data')
            self.assertEqual(1, subprocess.run(command).returncode)

if __name__ == '__main__':
    unittest.main()
