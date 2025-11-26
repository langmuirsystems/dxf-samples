///usr/bin/env jbang "$0" "$@" ; exit $?
//JAVA 21
//DEPS info.picocli:picocli:4.7.5
//DEPS org.openjfx:javafx-controls:21.0.1
//DEPS org.openjfx:javafx-graphics:21.0.1

import picocli.CommandLine;
import picocli.CommandLine.Command;

import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.image.Image;
import javafx.scene.image.PixelReader;
import javafx.scene.image.PixelWriter;
import javafx.scene.image.WritableImage;
import javafx.scene.paint.Color;
import javafx.stage.DirectoryChooser;
import javafx.stage.Stage;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.Callable;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;

@Command(name = "ImageEnhancer", mixinStandardHelpOptions = true, 
        version = "ImageEnhancer 1.0",
        description = "Enhances PNG images by increasing brightness and contrast by 25%")
public class ImageEnhancer implements Callable<Integer> {
    
    private static final String CONFIG_FILE = "ImageEnhancer.properties";
    private static final String LAST_FOLDER_KEY = "LastFolder";
    private static final double BRIGHTNESS_INCREASE = 0.25; // 25% increase
    private static final double CONTRAST_INCREASE = 0.25; // 25% increase
    
    public static void main(String... args) {
        // Start JavaFX toolkit
        FxStarter.startFx();
        
        int exitCode = new CommandLine(new ImageEnhancer()).execute(args);
        System.exit(exitCode);
    }

    @Override
    public Integer call() throws Exception {
        // Get folder path from user
        String folderPath = selectFolder();
        if (folderPath == null || folderPath.isEmpty()) {
            System.out.println("No folder selected. Exiting...");
            return 1;
        }
        
        // Save selected folder for next run
        saveLastFolder(folderPath);
        
        // Get all subfolders
        List<Path> subfolders = getSubfolders(folderPath);
        
        if (subfolders.isEmpty()) {
            System.out.println("No subfolders found in: " + folderPath);
            return 1;
        }
        
        System.out.println("Found " + subfolders.size() + " subfolders to process");
        
        // Process with virtual threads
        AtomicInteger totalProcessed = new AtomicInteger(0);
        
        try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<CompletableFuture<Void>> futures = new ArrayList<>();
            
            for (Path subfolder : subfolders) {
                CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                    try {
                        int processed = processFolder(subfolder);
                        totalProcessed.addAndGet(processed);
                    } catch (Exception e) {
                        System.err.println("Error processing folder " + subfolder + ": " + e.getMessage());
                        e.printStackTrace();
                    }
                }, executor);
                
                futures.add(future);
            }
            
            // Wait for all tasks to complete
            CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        }
        
        System.out.println("Total files processed: " + totalProcessed.get());
        System.out.println("Processing complete!");
        return 0;
    }
    
    private String selectFolder() {
        AtomicReference<String> selectedPath = new AtomicReference<>();
        CountDownLatch latch = new CountDownLatch(1);
        
        // Get last used folder
        String lastFolder = getLastFolder();
        
        Platform.runLater(() -> {
            try {
                DirectoryChooser chooser = new DirectoryChooser();
                chooser.setTitle("Select a folder containing subfolders with PNG files");
                
                // Set last folder if available
                if (lastFolder != null && !lastFolder.isEmpty()) {
                    File lastDir = new File(lastFolder);
                    if (lastDir.exists() && lastDir.isDirectory()) {
                        chooser.setInitialDirectory(lastDir);
                    }
                }
                
                // Create a temporary stage just for dialog
                Stage stage = new Stage();
                File selectedFolder = chooser.showDialog(stage);
                
                if (selectedFolder != null) {
                    selectedPath.set(selectedFolder.getAbsolutePath());
                }
            } catch (Exception e) {
                System.err.println("Error showing folder selection dialog: " + e.getMessage());
            } finally {
                latch.countDown();
            }
        });
        
        try {
            latch.await(); // Wait for the dialog to complete
            return selectedPath.get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("Folder selection was interrupted");
            return null;
        }
    }
    
    private String getLastFolder() {
        File configFile = new File(CONFIG_FILE);
        if (!configFile.exists()) {
            return null;
        }
        
        Properties props = new Properties();
        try (FileInputStream in = new FileInputStream(configFile)) {
            props.load(in);
            return props.getProperty(LAST_FOLDER_KEY);
        } catch (IOException e) {
            System.err.println("Error reading config file: " + e.getMessage());
            return null;
        }
    }
    
    private void saveLastFolder(String folderPath) {
        Properties props = new Properties();
        
        // Load existing properties if file exists
        File configFile = new File(CONFIG_FILE);
        if (configFile.exists()) {
            try (FileInputStream in = new FileInputStream(configFile)) {
                props.load(in);
            } catch (IOException e) {
                System.err.println("Error reading existing config: " + e.getMessage());
            }
        }
        
        // Set the last folder property
        props.setProperty(LAST_FOLDER_KEY, folderPath);
        
        // Save the properties
        try (FileOutputStream out = new FileOutputStream(configFile)) {
            props.store(out, "ImageEnhancer Configuration");
        } catch (IOException e) {
            System.err.println("Error saving config: " + e.getMessage());
        }
    }
    
    private List<Path> getSubfolders(String folderPath) throws IOException {
        List<Path> subfolders = new ArrayList<>();
        
        try (Stream<Path> paths = Files.list(Paths.get(folderPath))) {
            paths.filter(Files::isDirectory)
                 .filter(path -> !path.getFileName().toString().equals(".git") && 
                                !path.getFileName().toString().equals(".idea"))
                 .forEach(subfolders::add);
        }
        
        return subfolders;
    }
    
    private int processFolder(Path folderPath) throws IOException {
        System.out.println("Processing folder: " + folderPath);
        
        List<Path> pngFiles = new ArrayList<>();
        
        // Find all PNG files
        try (Stream<Path> paths = Files.list(folderPath)) {
            paths.filter(Files::isRegularFile)
                 .filter(path -> path.toString().toLowerCase().endsWith(".png"))
                 .forEach(pngFiles::add);
        }
        
        if (pngFiles.isEmpty()) {
            System.out.println("No PNG files found in: " + folderPath);
            return 0;
        }
        
        System.out.println("Found " + pngFiles.size() + " PNG files in: " + folderPath);
        
        // Process each PNG file
        AtomicInteger processedCount = new AtomicInteger(0);
        
        // Create a virtual thread per image for even better performance
        try (ExecutorService imageExecutor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<CompletableFuture<Void>> futures = new ArrayList<>();
            
            for (Path pngFile : pngFiles) {
                CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                    try {
                        enhanceImage(pngFile);
                        int count = processedCount.incrementAndGet();
                        System.out.println("Processed (" + count + "/" + pngFiles.size() + "): " + pngFile.getFileName());
                    } catch (Exception e) {
                        System.err.println("Error processing image " + pngFile + ": " + e.getMessage());
                        e.printStackTrace();
                    }
                }, imageExecutor);
                
                futures.add(future);
            }
            
            // Wait for all image processing to complete
            CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        }
        
        System.out.println("Processed " + processedCount.get() + " PNG files in: " + folderPath);
        return processedCount.get();
    }
    
    private void enhanceImage(Path imagePath) throws Exception {
        // Load the image
        BufferedImage bufferedImage = ImageIO.read(imagePath.toFile());
        
        // Convert to JavaFX Image
        Image originalImage = convertToFXImage(bufferedImage);
        
        // Process the image
        WritableImage enhancedImage = adjustBrightnessAndContrast(originalImage, BRIGHTNESS_INCREASE, CONTRAST_INCREASE);
        
        // Convert back to BufferedImage and save
        BufferedImage resultImage = convertFromFXImage(enhancedImage);
        ImageIO.write(resultImage, "PNG", imagePath.toFile());
    }
    
    private Image convertToFXImage(BufferedImage bufferedImage) {
        // Create a new JavaFX Image
        WritableImage writableImage = new WritableImage(bufferedImage.getWidth(), bufferedImage.getHeight());
        PixelWriter pixelWriter = writableImage.getPixelWriter();
        
        // Copy pixel data from BufferedImage to JavaFX Image
        for (int x = 0; x < bufferedImage.getWidth(); x++) {
            for (int y = 0; y < bufferedImage.getHeight(); y++) {
                int argb = bufferedImage.getRGB(x, y);
                
                int alpha = (argb >> 24) & 0xff;
                int red = (argb >> 16) & 0xff;
                int green = (argb >> 8) & 0xff;
                int blue = argb & 0xff;
                
                Color color = Color.rgb(red, green, blue, alpha / 255.0);
                pixelWriter.setColor(x, y, color);
            }
        }
        
        return writableImage;
    }
    
    private BufferedImage convertFromFXImage(Image image) {
        int width = (int) image.getWidth();
        int height = (int) image.getHeight();
        BufferedImage bufferedImage = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        
        PixelReader pixelReader = image.getPixelReader();
        
        for (int x = 0; x < width; x++) {
            for (int y = 0; y < height; y++) {
                Color color = pixelReader.getColor(x, y);
                
                int alpha = (int) (color.getOpacity() * 255);
                int red = (int) (color.getRed() * 255);
                int green = (int) (color.getGreen() * 255);
                int blue = (int) (color.getBlue() * 255);
                
                int argb = (alpha << 24) | (red << 16) | (green << 8) | blue;
                bufferedImage.setRGB(x, y, argb);
            }
        }
        
        return bufferedImage;
    }
    
    private WritableImage adjustBrightnessAndContrast(Image inputImage, double brightnessIncrease, double contrastIncrease) {
        int width = (int) inputImage.getWidth();
        int height = (int) inputImage.getHeight();
        
        PixelReader reader = inputImage.getPixelReader();
        WritableImage outputImage = new WritableImage(width, height);
        PixelWriter writer = outputImage.getPixelWriter();
        
        // Apply brightness and contrast adjustment
        for (int x = 0; x < width; x++) {
            for (int y = 0; y < height; y++) {
                Color color = reader.getColor(x, y);
                
                // Apply brightness increase
                double r = color.getRed() + brightnessIncrease * (1.0 - color.getRed());
                double g = color.getGreen() + brightnessIncrease * (1.0 - color.getGreen());
                double b = color.getBlue() + brightnessIncrease * (1.0 - color.getBlue());
                
                // Clamp values to [0,1]
                r = Math.min(1.0, Math.max(0.0, r));
                g = Math.min(1.0, Math.max(0.0, g));
                b = Math.min(1.0, Math.max(0.0, b));
                
                // Apply contrast increase (using standard contrast formula)
                r = ((r - 0.5) * (1.0 + contrastIncrease)) + 0.5;
                g = ((g - 0.5) * (1.0 + contrastIncrease)) + 0.5;
                b = ((b - 0.5) * (1.0 + contrastIncrease)) + 0.5;
                
                // Clamp values again
                r = Math.min(1.0, Math.max(0.0, r));
                g = Math.min(1.0, Math.max(0.0, g));
                b = Math.min(1.0, Math.max(0.0, b));
                
                // Create new color with adjusted values
                Color newColor = new Color(r, g, b, color.getOpacity());
                writer.setColor(x, y, newColor);
            }
        }
        
        return outputImage;
    }

    // Helper class to start JavaFX
    public static class FxStarter extends Application {
        private static final CountDownLatch LATCH = new CountDownLatch(1);
        
        public static void startFx() {
            // Start JavaFX in a separate thread
            Thread t = new Thread(() -> Application.launch(FxStarter.class));
            t.setDaemon(true);
            t.start();
            
            try {
                LATCH.await(); // Wait for JavaFX to start
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        
        @Override
        public void start(Stage primaryStage) {
            // Don't show the primary stage, we only need the JavaFX toolkit
            Platform.setImplicitExit(false);
            LATCH.countDown(); // Signal that JavaFX has started
        }
    }
}