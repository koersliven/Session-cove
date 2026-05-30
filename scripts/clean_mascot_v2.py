import os
import requests
from PIL import Image, ImageDraw

def download_image(url, path):
    response = requests.get(url)
    if response.status_code == 200:
        with open(path, 'wb') as f:
            f.write(response.content)
        return True
    return False

def flood_fill_transparency(image_path, output_path):
    img = Image.open(image_path).convert("RGBA")
    width, height = img.size
    
    # Create a mask for pixels to remove
    # The checkerboard in these images typically uses these two grays
    # We also check for near-white/gray if there's compression noise
    def is_bg(pixel):
        r, g, b, a = pixel
        # Standard checkerboard colors
        if (r, g, b) == (204, 204, 204) or (r, g, b) == (255, 255, 255):
            return True
        # Slightly off due to artifacts
        if abs(r-g) < 5 and abs(g-b) < 5 and r > 150:
            return True
        return False

    data = img.getdata()
    new_data = []
    
    # Simple strategy: if it looks like background, it's out.
    # The octopus colors are very distinct (Coral/Blue).
    # Coral R is usually > 200, G < 150, B < 150.
    # Blue R < 100, G < 150, B > 150.
    
    for item in data:
        if is_bg(item):
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append(item)
            
    img.putdata(new_data)
    img.save(output_path, "PNG")

if __name__ == "__main__":
    tasks = [
        ("https://sc02.alicdn.com/kf/A21d460232664be983f711d9caa5c3adeO.png", "SessionCove/Resources/claude_idle.png"),
        ("https://sc02.alicdn.com/kf/A5f6cb10af6f54c9da41571476e339179Q.png", "SessionCove/Resources/claude_attention.png"),
        ("https://sc02.alicdn.com/kf/Af6cd976d7623489bb0bdb2487a021b0bT.png", "reference/claude_wink.png")
    ]
    
    for url, path in tasks:
        if download_image(url, path):
            flood_fill_transparency(path, path)
            print(f"Processed {path}")
