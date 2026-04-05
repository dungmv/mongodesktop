# MongoDesktop

[English](README.md) | [Tiếng Việt](README_VN.md)

A native, lightweight MongoDB client for macOS built with SwiftUI and the MongoDB C Driver.

![App Screenshot](https://via.placeholder.com/800x450?text=MongoDesktop+Preview)

## Features

- **🚀 Native Performance**: Built with SwiftUI for a smooth, high-performance experience on macOS.
- **🔌 Flexible Connections**: Support for standard `mongodb://` and `mongodb+srv://` (DNS seed list) connection strings.
- **📁 Database Explorer**: Easily navigate through databases and collections.
- **🔍 Query Engine**: Run queries with support for filters, sorting, and projections.
- **📑 Tabbed Interface**: Work with multiple collections or queries simultaneously using a familiar tabbed layout.
- **🛡️ Secure**: Passwords are saved securely (via macOS Keychain integration in the future, currently profile-based management).
- **🛠️ DNS Troubleshooting**: Integrated `DNSDebugService` to help diagnose connection issues with SRV records.

## Requirements

- macOS 13.0 or later (Ventura+)
- Xcode 14.0+ (for building from source)
- `libmongoc` and `libbson` (MongoDB C Driver)

## Technical Architecture

MongoDesktop uses a modern Swift architecture:
- **SwiftUI**: For the entire user interface, ensuring a native look and feel.
- **Actors**: Using Swift's `actor` model in `MongoService` to ensure thread-safe interactions with the underlying C driver.
- **MongoDB C Driver**: Leveraged for robust, low-level protocol communication with MongoDB servers.
- **Bridging**: High-performance bridging between Swift and C data structures (BSON/JSON).

## Getting Started

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/MongoDesktop.git
   ```
2. Open `MongoDesktop.xcodeproj` in Xcode.
3. Build and Run (**Cmd + R**).

*Note: Ensure you have the MongoDB C Driver dependencies linked correctly if building for the first time.*

### Usage

1. **Add Connection**: Click the "+" button to add a new MongoDB connection profile.
2. **Test & Save**: Enter your connection URI, test the connection, and save the profile.
3. **Explore**: Double-click a connection to open the database explorer window.
4. **Query**: Select a collection and use the query bar to search for documents.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request or open an issue for bugs and feature requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
