# PixelFlow

A file/text transfer tool based on QR codes

## Introduction

PixelFlow is a lightweight, browser-based data transfer tool that transmits files or text between devices via QR codes. No application installation is required—simply open it in any modern browser to use.

## Features

- **Dual Transfer Modes**: Supports both file and text transfer modes
- **QR Code Chunking**: Splits data into multiple QR codes to handle large data transfers
- **Real-time Progress Display**: Shows transfer progress and chunk status
- **Cross-platform Compatibility**: Built on web technologies, compatible with all modern browsers
- **No Server Required**: Pure client-side operation; data never passes through any server

## File Structure

```
├── index.html      # Receiver page (Reader)
├── sender.html     # Sender page (Sender)
├── qrcode.min.js   # QR code generation library
├── LICENSE         # Open source license
└── .gitignore      # Git ignore configuration
```

## Usage

### Sender (sender.html)

1. Open `sender.html` on your computer or mobile device
2. Select the transfer mode:
   - **File Mode**: Click to select a file or drag and drop it into the designated area
   - **Text Mode**: Directly input content into the text box
3. The system automatically splits the data into multiple QR code chunks
4. Use the receiving device to scan the displayed QR codes to begin transmission

### Receiver (index.html)

1. Open `index.html` on another device
2. Use the camera to scan the QR codes displayed by the sender
3. The system automatically receives and reassembles all data chunks
4. Once complete, view or download the transferred content

## Technical Overview

- Uses QR codes as the data transmission medium
- Splits large files or long text into multiple data chunks
- Each chunk is independently encoded into a QR code
- The receiver scans and collects all chunks, then reassembles them into the original data

## Dependencies

- [qrcode.js](https://github.com/davidshimjs/qrcodejs) - For generating QR codes

## License

MIT License

## Notes

- Ensure the scanning device has sufficient lighting to capture clear QR code images
- Large files will generate many QR code chunks, potentially increasing transfer time
- Recommended for use in stable network environments