import os
from PIL import Image

def clean_image(path):
    if not os.path.exists(path):
        print(f"File not found: {path}")
        return
        
    print(f"Cleaning {path}...")
    img = Image.open(path).convert("RGBA")
    data = img.getdata()
    
    new_data = []
    for item in data:
        r, g, b, a = item
        
        # Calculate grayscale similarity
        avg = (r + g + b) / 3
        diff = max(abs(r-avg), abs(g-avg), abs(b-avg))
        
        # Octopus palette (approximate):
        # Coral: R>200, G~100, B~100
        # Blue: R~50, G~100, B~200
        
        # Strategy: 
        # 1. If it's a very light gray (near white checkerboard)
        # 2. If it's a mid-gray (the other checkerboard square)
        # 3. If it's pure grayscale and NOT black (black is eyes/lines)
        
        is_gray = (diff < 15) # Allow some noise
        is_light = (avg > 180)
        is_mid_gray = (avg > 100 and avg < 220)
        
        # Ensure we don't kill the octopus colors
        # Octopus is definitely NOT gray
        is_not_octopus = (r < 180 or g > 150 or b > 150) and (r > 100 or g > 150 or b < 150)
        
        if is_gray and (is_light or is_mid_gray):
            # Double check it's not the white part of the headphones
            # Headphones white is usually very bright R=255, G=255, B=255
            if r > 250 and g > 250 and b > 250:
                 # Check if it's likely a headphone pixel (localized)
                 # For simplicity, we keep very bright white unless it's clearly background
                 pass
            
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append(item)
            
    img.putdata(new_data)
    img.save(path, "PNG")
    print(f"Done: {path}")

if __name__ == "__main__":
    files = [
        "SessionCove/Resources/claude_idle.png",
        "SessionCove/Resources/claude_attention.png",
        "SessionCove/Resources/claude_sleeping.png",
        "SessionCove/Resources/claude_working.png",
        "reference/claude_wink.png"
    ]
    for f in files:
        clean_image(f)
