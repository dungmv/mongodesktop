import SwiftUI

struct ServerInfoPopoverView: View {
    @State private var serverInfo: ServerInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MongoDB Server Info")
                .font(.headline)
                .padding(.bottom, 4)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            } else if let info = serverInfo {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Host", value: info.hostURI)
                    InfoRow(label: "Edition", value: "MongoDB \(info.version)")
                    InfoRow(label: "Cluster Mode", value: info.clusterMode)
                    InfoRow(label: "Stats", value: "\(info.databasesCount) DBs, \(info.collectionsCount) Collections")
                }
            }
        }
        .padding()
        .frame(width: 320)
        .task {
            do {
                serverInfo = try await MongoService.shared.getServerInfo()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
    }
}
