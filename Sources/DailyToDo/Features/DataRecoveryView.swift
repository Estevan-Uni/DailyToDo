import SwiftUI

struct DataRecoveryView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
            Text("暂时无法打开本机数据").font(.title2.weight(.semibold))
            Text(model.loadFailure ?? "数据库尚未打开。").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text("恢复会创建独立新库，原文件保留；也可以修复文件后重新尝试。").font(.callout)
            HStack {
                Button("从 JSON 备份恢复…") { Task { await model.recoverStorage(fromBackup: true) } }.buttonStyle(.borderedProminent)
                Button("重新尝试") { Task { await model.retryStorage() } }
            }
            HStack {
                Button("显示原数据文件夹") { NSWorkspace.shared.activateFileViewerSelecting([model.storageURL.deletingLastPathComponent()]) }
                Button("创建独立空白数据…") { Task { await model.recoverStorage(fromBackup: false) } }
            }.font(.caption)
        }.padding(40).frame(maxWidth: 660, alignment: .leading).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
    }
}
