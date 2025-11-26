import rhinoscriptsyntax as rs
import os
import Rhino
import System
import scriptcontext as sc
import ConfigParser  # Python 2.7 uses ConfigParser (not configparser as in Python 3)

def get_script_path():
    """Returns the path of the current script file"""
    return os.path.abspath(os.path.dirname(__file__))

def get_config_path():
    """Returns the path to the config file with the same base name as the script"""
    script_path = get_script_path()
    script_name = os.path.splitext(os.path.basename(__file__))[0]
    return os.path.join(script_path, script_name + ".ini")

def get_last_folder():
    """Retrieves the last used folder path from the config file"""
    config_path = get_config_path()
    
    if not os.path.exists(config_path):
        return None
    
    try:
        config = ConfigParser.ConfigParser()
        config.read(config_path)
        if config.has_section("Settings") and config.has_option("Settings", "LastFolder"):
            return config.get("Settings", "LastFolder")
    except Exception as e:
        print("Error reading config file: {}".format(e))
    
    return None

def save_last_folder(folder_path):
    """Saves the last used folder path to the config file"""
    config_path = get_config_path()
    
    try:
        config = ConfigParser.ConfigParser()
        
        # Read existing config if it exists
        if os.path.exists(config_path):
            config.read(config_path)
        
        # Ensure the section exists
        if not config.has_section("Settings"):
            config.add_section("Settings")
        
        # Set the last folder path
        config.set("Settings", "LastFolder", folder_path)
        
        # Write the config to file
        with open(config_path, 'w') as config_file:
            config.write(config_file)
    except Exception as e:
        print("Error saving config file: {}".format(e))

def main():
    # Get the last used folder path
    last_folder = get_last_folder()
    
    # 1. Ask user to select a folder, starting from the last used folder if available
    folder_path = rs.BrowseForFolder(last_folder, "Select a folder containing subfolders with DXF files")
    if not folder_path:
        print("No folder selected. Script cancelled.")
        return
    
    # Save the selected folder for next time
    save_last_folder(folder_path)
    
    # 2. Get all subfolders in the selected folder
    try:
        # Python 2 compatible way to get subfolders, excluding .git and .idea folders
        subfolders = [os.path.join(folder_path, f) for f in os.listdir(folder_path) 
                     if os.path.isdir(os.path.join(folder_path, f)) 
                     and f != '.git' and f != '.idea']
    except Exception as e:
        print("Error accessing subfolders: {}".format(e))
        return
    
    if not subfolders:
        print("No subfolders found in {}".format(folder_path))
        return
    
    print("Found {} subfolders to process".format(len(subfolders)))
    
    # Store the original document for later restoration
    original_doc = sc.doc
    
    try:
        # 3. Process each subfolder
        for subfolder in subfolders:
            process_subfolder(subfolder)
    finally:
        # Restore the original document
        sc.doc = original_doc
    
    print("Processing complete!")

def process_subfolder(subfolder_path):
    # Find all DXF files in the subfolder
    dxf_files = [f for f in os.listdir(subfolder_path) if f.lower().endswith('.dxf')]
    
    if not dxf_files:
        print("No DXF files found in {}".format(subfolder_path))
        return
    
    print("Processing {} DXF files in {}".format(len(dxf_files), subfolder_path))
    
    # Process each DXF file
    for dxf_file in dxf_files:
        dxf_path = os.path.join(subfolder_path, dxf_file)
        process_dxf_file(dxf_path)

def process_dxf_file(dxf_path):
    filename = os.path.basename(dxf_path)
    folder = os.path.dirname(dxf_path)
    
    print("Processing: {}".format(filename))
    
    # Create a new document, forcing it without dialog
    rs.DocumentModified(False)  # Mark current document as not modified
    rs.Command("_-New _None _Enter", echo=False)
    
    # Clear the document to ensure we have a fresh slate
    rs.Command("_-SelAll _Enter", echo=False)
    rs.Command("_-Delete _Enter", echo=False)
    
    # Import the DXF file
    rs.Command('_-Import "{}" _Enter'.format(dxf_path), echo=False)
    
    # Wait a moment for the import to complete
    System.Threading.Thread.Sleep(100)
    
    # Select all objects for zooming purposes
    rs.Command("_-SelAll _Enter", echo=False)
    
    # Try to set Top view using a direct command
    rs.Command("_Top", echo=False)
    
    # Zoom extents with a margin (with corrected syntax)
    rs.Command("_-Zoom _Extents _Enter", echo=False)
    rs.Command("_-Zoom All 0.8 _Enter", echo=False)  # Zoom out a bit for margin
    
    # Try to maximize the viewport using just the MaxViewport command
    rs.Command("_-MaxViewport _Enter", echo=False)
    
    # Clear the selection using the RhinoScript API directly
    # This should be more reliable than the _-SelNone command
    rs.UnselectAllObjects()
    
    # Wait a moment for the view to update
    System.Threading.Thread.Sleep(100)
    
    # Create a screenshot with the same name as the DXF file
    screenshot_path = os.path.join(folder, os.path.splitext(filename)[0] + ".png")
    
    # Take the screenshot using ScreenCaptureToFile
    rs.Command('_-ScreenCaptureToFile "{}" _Enter'.format(screenshot_path), echo=False)
    
    print("Screenshot saved: {}".format(screenshot_path))
    
    # Mark document as not modified to avoid save prompt
    rs.DocumentModified(False)

# Run the script
if __name__ == "__main__":
    main()