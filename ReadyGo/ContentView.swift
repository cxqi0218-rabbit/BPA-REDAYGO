import SwiftUI
import UserNotifications
import UIKit
import Speech
import AVFoundation

private enum Palette {
    static let background = Color(red: 0.90, green: 0.93, blue: 0.95)
    static let ink = Color(red: 0.10, green: 0.16, blue: 0.21)
    static let green = Color(red: 0.16, green: 0.38, blue: 0.43)
}

private struct GlassBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let path = Bundle.main.path(forResource: "EntrywayBackground", ofType: "jpg"), let photo = UIImage(contentsOfFile: path) {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().blur(radius: 6)
                } else { Palette.background }
                Color(red: 0.91, green: 0.94, blue: 0.94).opacity(0.32)
                LinearGradient(colors: [.white.opacity(0.25), .clear, Color(red: 0.79, green: 0.86, blue: 0.89).opacity(0.28)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 0.70, green: 0.85, blue: 0.88).opacity(0.55)).frame(width: geometry.size.width * 0.85).blur(radius: 80).offset(x: geometry.size.width * 0.35, y: -geometry.size.height * 0.28)
                Circle().fill(Color(red: 0.84, green: 0.82, blue: 0.92).opacity(0.45)).frame(width: geometry.size.width * 0.8).blur(radius: 85).offset(x: -geometry.size.width * 0.35, y: geometry.size.height * 0.28)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct Outing: Identifiable, Codable {
    var id = UUID()
    var title: String
    var date: Date?
    var items: [PackingItem] = []
    var reminderDate: Date? = nil
    var isInbox: Bool? = nil
}

private struct PackingItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var needsPreparation: Bool
    var needsCarrying: Bool
    var prepared = false
    var carried = false
    var skipped = false
    var preparerID: UUID? = nil
    var carrierID: UUID? = nil
}

private struct FamilyMember: Identifiable, Codable {
    var id = UUID()
    var name: String
}

@MainActor private final class Store: ObservableObject {
    @Published var outings: [Outing] = [] { didSet { save() } }
    @Published var members: [FamilyMember] = [] { didSet { saveMembers() } }
    private let key = "readygo.outings.v1"
    private let memberKey = "readygo.members.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode([Outing].self, from: data) { outings = value }
        if let data = UserDefaults.standard.data(forKey: memberKey), let value = try? JSONDecoder().decode([FamilyMember].self, from: data) { members = value }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(outings) { UserDefaults.standard.set(data, forKey: key) }
    }
    private func saveMembers() { if let data = try? JSONEncoder().encode(members) { UserDefaults.standard.set(data, forKey: memberKey) } }
    func memberName(_ id: UUID?) -> String { members.first(where: { $0.id == id })?.name ?? "未指定" }
    func removeMember(_ id: UUID) {
        members.removeAll { $0.id == id }
        for index in outings.indices {
            for itemIndex in outings[index].items.indices {
                if outings[index].items[itemIndex].preparerID == id { outings[index].items[itemIndex].preparerID = nil }
                if outings[index].items[itemIndex].carrierID == id { outings[index].items[itemIndex].carrierID = nil }
            }
        }
    }
    func add(_ outing: Outing) { outings.append(outing) }
    func delete(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        outings.removeAll { $0.id == id }
    }
    func update(_ outing: Outing) {
        guard let index = outings.firstIndex(where: { $0.id == outing.id }) else { return }
        outings[index] = outing
    }
}

private struct SoftCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.15), .white.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: Color(red: 0.19, green: 0.29, blue: 0.35).opacity(0.14), radius: 24, x: 0, y: 12)
    }
}
private extension View { func softCard() -> some View { modifier(SoftCard()) } }

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var showingNew = false
    @State private var showingQuick = false
    var body: some View {
        TabView {
            NavigationStack { HomeView(store: store, showingNew: $showingNew, showingQuick: $showingQuick) }
                .tabItem { Label("今天", systemImage: "house") }
            NavigationStack { ListView(store: store, showingNew: $showingNew) }
                .tabItem { Label("清单", systemImage: "checklist") }
            NavigationStack { FamilyView(store: store) }
                .tabItem { Label("家庭", systemImage: "person.2") }
            NavigationStack { DeviceView() }
                .tabItem { Label("设备", systemImage: "display") }
            NavigationStack { SettingsView(store: store) }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(Palette.green)
        .sheet(isPresented: $showingNew) { NewOutingView(store: store) }
        .sheet(isPresented: $showingQuick) { QuickCaptureView(store: store) }
    }
}

private struct HomeView: View {
    @ObservedObject var store: Store
    @Binding var showingNew: Bool
    @Binding var showingQuick: Bool
    private var upcoming: [Outing] { store.outings.filter { $0.date == nil || $0.date! >= Calendar.current.startOfDay(for: Date()) }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) } }
    var body: some View {
        ZStack {
            GlassBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide))).font(.subheadline.weight(.medium)).foregroundStyle(Palette.green)
                        Text("从容出发。").font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("为每一次出门，留一份从容。 ").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                    if let outing = upcoming.first {
                        HStack { Text("接下来的安排").font(.headline); Spacer(); Text("NEXT UP").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary) }
                        NavigationLink { OutingDetail(store: store, id: outing.id) } label: { OutingCard(outing: outing) }.buttonStyle(.plain)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.green)
                            Text("为下一次出发做好准备").font(.title3.weight(.semibold))
                            Text("例如：明天上班带书给同事。可以先记下来，稍后再关联出门安排。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).softCard()
                    }
                    Button { showingQuick = true } label: { Label("记一件事", systemImage: "plus").foregroundStyle(.white).frame(maxWidth: .infinity).padding(16) }
                        .buttonStyle(.borderedProminent).tint(Palette.green)
                    Button { showingNew = true } label: { Label("计划一次出门", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity).padding(14) }.buttonStyle(.bordered).tint(Palette.green)
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.seal").foregroundStyle(Palette.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("清晰的准备，从容的出发").font(.subheadline.bold())
                            Text("想到就记；需要提前处理的事和临走要带的东西，可以分别确认。 ").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).softCard()
                }.padding(24)
            }
        }.foregroundStyle(Palette.ink).navigationTitle("ReadyGo").navigationBarTitleDisplayMode(.inline)
    }
}


private struct QuickCaptureView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selectedID: UUID?
    @State private var prepare = false
    @State private var carry = true
    @State private var showingSpeech = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showingSpeech = true } label: { Label("语音转文字", systemImage: "mic") }
                    TextField("例如：明天带书给同事", text: $text, axis: .vertical).lineLimit(2...5)
                } header: { Text("想到什么，先记下来") } footer: { Text("文字会原样保存；时间和出门安排需要手动选择。") }
                Section("放在哪里") {
                    Picker("关联出门", selection: $selectedID) {
                        Text("先存到随手记").tag(nil as UUID?)
                        ForEach(store.outings.filter { $0.isInbox != true }) { outing in Text(outing.title).tag(outing.id as UUID?) }
                    }
                }
                Section("需要做什么") {
                    Toggle("提前准备", isOn: $prepare)
                    Toggle("临走携带", isOn: $carry)
                }
            }.navigationTitle("记一件事").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingSpeech) { SpeechCaptureView { text = $0 } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!prepare && !carry)) }
                }
        }
    }
    private func save() {
        let item = PackingItem(title: text.trimmingCharacters(in: .whitespacesAndNewlines), needsPreparation: prepare, needsCarrying: carry)
        if let id = selectedID, var outing = store.outings.first(where: { $0.id == id }) { outing.items.append(item); store.update(outing) }
        else if var inbox = store.outings.first(where: { $0.isInbox == true }) { inbox.items.append(item); store.update(inbox) }
        else { store.add(Outing(title: "随手记", date: nil, items: [item], isInbox: true)) }
        dismiss()
    }
}


@MainActor private final class SpeechCapture: ObservableObject {
    @Published var transcript = ""
    @Published var message = "点击开始后说话。"
    @Published var recording = false
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    func start() async {
        let speechAllowed = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        guard speechAllowed else { message = "语音识别权限未开启，请在系统设置中开启。"; return }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard micAllowed else { message = "麦克风权限未开启，请在系统设置中开启。"; return }
        guard let recognizer, recognizer.isAvailable else { message = "语音识别暂不可用，请使用文字输入。"; return }
        do {
            task?.cancel(); transcript = ""
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            engine.prepare(); try engine.start()
            recording = true; message = "正在聆听…"
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop(); if error != nil && self.transcript.isEmpty { self.message = "识别未完成，请重试或输入文字。" } }
                }
            }
        } catch { stop(); message = "无法启动录音，请重试或输入文字。" }
    }
    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !transcript.isEmpty { message = "请检查识别文字后使用。" }
    }
    func cancel() { stop(); task?.cancel(); task = nil }
}
private struct SpeechCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCapture()
    let onUse: (String) -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: speech.recording ? "waveform.circle.fill" : "mic.circle").font(.system(size: 70)).foregroundStyle(Palette.green)
                Text(speech.message).font(.headline)
                TextEditor(text: $speech.transcript).frame(minHeight: 120, maxHeight: 200).padding(8).background(Palette.background, in: RoundedRectangle(cornerRadius: 18)).accessibilityLabel("识别文字，可编辑")
                Button(speech.recording ? "停止录音" : "开始录音") { if speech.recording { speech.stop() } else { Task { await speech.start() } } }.buttonStyle(.borderedProminent).tint(Palette.green)
                Text("语音可能由系统的识别服务处理，识别后请检查文字。 ").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }.padding(24).navigationTitle("语音转文字").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { speech.cancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("使用文字") { speech.cancel(); onUse(speech.transcript); dismiss() }.disabled(speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onDisappear { speech.cancel() }
        }
    }
}

private struct OutingCard: View {
    let outing: Outing
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(outing.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "时间待安排")
                .font(.subheadline).foregroundStyle(Palette.green)
            Text(outing.title).font(.title2.weight(.semibold))
            Text("\(outing.items.filter { $0.needsPreparation && !$0.prepared }.count) 项待准备 · \(outing.items.filter { $0.needsCarrying && !$0.carried && !$0.skipped }.count) 项待携带")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack { Text("查看清单"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline.weight(.semibold)).padding(.top, 10)
        }.frame(maxWidth: .infinity, alignment: .leading).softCard()
    }
}

private struct ListView: View {
    @ObservedObject var store: Store
    @Binding var showingNew: Bool
    var body: some View {
        ZStack {
            GlassBackdrop()
            if store.outings.isEmpty {
                ContentUnavailableView("还没有出门安排", systemImage: "checklist", description: Text("新建一次出门，开始整理需要准备的事。"))
            } else {
                List {
                    ForEach(store.outings.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }) { outing in
                        NavigationLink { OutingDetail(store: store, id: outing.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(outing.title).font(.headline)
                                Text(outing.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "时间待安排").font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                        .swipeActions { Button("删除", role: .destructive) { store.delete(outing.id) } }
                    }
                }.scrollContentBackground(.hidden)
            }
        }.navigationTitle("我的清单").toolbar { Button { showingNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("新建出门") }
    }
}

private struct NewOutingView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var template = "空白"
    var body: some View {
        NavigationStack {
            Form {
                Section("出门名称") { TextField("例如：上班、周末出游", text: $title) }
                Section("起始模板") { Picker("模板", selection: $template) { ForEach(["空白", "上班通勤", "带孩子外出", "短途出差"], id: \.self) { Text($0) } }; Text("创建后可自行删除或添加物品。 ").font(.footnote).foregroundStyle(.secondary) }
                Section("出发时间") {
                    Toggle("设置出发时间", isOn: $hasDate)
                    if hasDate { DatePicker("出发", selection: $date) }
                }
                Section { Text("可以先保存，之后再添加事项或修改时间。数据保存在这台设备上。 ").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("新建出门").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { let names: [String] = template == "上班通勤" ? ["钥匙", "手机", "工作用品"] : template == "带孩子外出" ? ["饮水", "备用衣物", "清洁用品"] : template == "短途出差" ? ["证件", "充电器", "换洗衣物"] : []; store.add(Outing(title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: hasDate ? date : nil, items: names.map { PackingItem(title: $0, needsPreparation: false, needsCarrying: true) })); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}

private struct OutingDetail: View {
    @ObservedObject var store: Store
    let id: UUID
    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var showingReminder = false
    @State private var editingItem: PackingItem?
    @State private var movingItem: PackingItem?
    private var outing: Outing? { store.outings.first { $0.id == id } }
    private func mutate(_ itemID: UUID, action: (inout PackingItem) -> Void) {
        guard var value = outing, let index = value.items.firstIndex(where: { $0.id == itemID }) else { return }
        action(&value.items[index]); store.update(value)
    }
    var body: some View {
        Group {
            if let value = outing {
                List {
                    Section {
                        Text(value.date.map { $0.formatted(date: .complete, time: .shortened) } ?? "出发时间待安排")
                        Text("仅保存在此设备").font(.footnote).foregroundStyle(.secondary)
                        Button { showingReminder = true } label: { Label(value.reminderDate.map { "提醒：" + $0.formatted(date: .abbreviated, time: .shortened) } ?? "设置出门提醒", systemImage: "bell") }
                    }
                    Section { if value.items.filter(\.needsPreparation).isEmpty { Text("暂无提前准备的事项").foregroundStyle(.secondary) }
                        ForEach(value.items.filter(\.needsPreparation)) { item in
                            Button { mutate(item.id) { $0.prepared.toggle() } } label: {
                                VStack(alignment: .leading, spacing: 4) { Label(item.title, systemImage: item.prepared ? "checkmark.circle.fill" : "circle"); if item.preparerID != nil { Text("准备：" + store.memberName(item.preparerID)).font(.caption).foregroundStyle(.secondary) } }
                                Spacer(); Text(item.prepared ? "已准备 · 撤销" : "标记已准备").font(.caption)
                            }.buttonStyle(.plain).accessibilityHint("切换准备状态")
                        }
                    } header: { Text("提前准备") } footer: { Text("准备完成不代表已经带走。") }
                    Section {
                        if value.items.filter(\.needsCarrying).isEmpty { Text("暂无携带事项").foregroundStyle(.secondary) }
                        ForEach(value.items.filter(\.needsCarrying)) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(item.title); Spacer(); Text(item.skipped ? "本次不带" : item.carried ? "已带走" : "待携带").font(.caption).foregroundStyle(.secondary) }
                                if item.carrierID != nil { Text("携带：" + store.memberName(item.carrierID)).font(.caption).foregroundStyle(.secondary) }
                                HStack {
                                    Button(item.carried ? "撤销带走" : "已带走") { mutate(item.id) { $0.carried.toggle(); $0.skipped = false } }
                                    Button(item.skipped ? "撤销跳过" : "本次不带") { mutate(item.id) { $0.skipped.toggle(); $0.carried = false } }
                                }.buttonStyle(.bordered).font(.caption)
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("临走带上") }
                    Section("所有事项") {
                        ForEach(value.items) { item in Button { editingItem = item } label: { HStack { Text(item.title); Spacer(); Image(systemName: "pencil").foregroundStyle(.secondary) } }.buttonStyle(.plain).swipeActions(edge: .leading) { Button("移动") { movingItem = item }.tint(Palette.green) }.swipeActions { Button("删除", role: .destructive) { var updated = value; updated.items.removeAll { $0.id == item.id }; store.update(updated) } } }
                    }
                }.scrollContentBackground(.hidden).background(GlassBackdrop()).navigationTitle(value.title).toolbar {
                    ToolbarItem(placement: .primaryAction) { Button("添加事项") { showingAdd = true } }
                    ToolbarItem(placement: .secondaryAction) { Button("编辑出门") { showingEdit = true } }
                }
                .sheet(isPresented: $showingAdd) { ItemEditor { item in if var updated = outing { updated.items.append(item); store.update(updated) } } }
                .sheet(isPresented: $showingEdit) { EditOutingView(store: store, outing: value) }
                .sheet(item: $movingItem) { item in MoveItemView(store: store, sourceID: id, item: item) }
                .sheet(item: $editingItem) { item in EditItemView(item: item, members: store.members) { changed in if var updated = outing, let index = updated.items.firstIndex(where: { $0.id == changed.id }) { updated.items[index] = changed; store.update(updated) } } }
                .sheet(isPresented: $showingReminder) { ReminderView(store: store, outing: value) }
            } else { ContentUnavailableView("出门安排已删除", systemImage: "calendar.badge.minus") }
        }
    }
}


private struct MoveItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    let sourceID: UUID
    let item: PackingItem
    @State private var destination: UUID?
    var body: some View {
        NavigationStack {
            Form {
                Section("选择目标出门") {
                    Picker("移动到", selection: $destination) {
                        Text("请选择").tag(nil as UUID?)
                        ForEach(store.outings.filter { $0.id != sourceID }) { outing in Text(outing.title).tag(outing.id as UUID?) }
                    }
                    if store.outings.filter({ $0.id != sourceID }).isEmpty { Text("请先创建另一条出门安排。 ").foregroundStyle(.secondary) }
                }
                Text("事项及其准备、携带状态会一起移动。 ").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("移动事项").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("移动") {
                    guard let destination, var source = store.outings.first(where: { $0.id == sourceID }), var target = store.outings.first(where: { $0.id == destination }), let current = source.items.first(where: { $0.id == item.id }) else { return }
                    source.items.removeAll { $0.id == item.id }; target.items.append(current); store.update(source); store.update(target); dismiss()
                }.disabled(destination == nil) }
            }
        }
    }
}

private struct ItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (PackingItem) -> Void
    @State private var title = ""
    @State private var prepare = false
    @State private var carry = true
    var body: some View {
        NavigationStack {
            Form {
                TextField("例如：电脑、给电脑充电", text: $title)
                Section("需要做什么") {
                    Toggle("提前准备", isOn: $prepare)
                    Toggle("临走携带", isOn: $carry)
                }
                Text("两项都选择时，可以分别确认准备和携带。 ").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("添加事项").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(PackingItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), needsPreparation: prepare, needsCarrying: carry)); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!prepare && !carry)) }
                }
        }
    }
}

private struct EditOutingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    @State var outing: Outing
    @State private var hasDate: Bool
    @State private var date: Date
    init(store: Store, outing: Outing) {
        self.store = store; _outing = State(initialValue: outing)
        _hasDate = State(initialValue: outing.date != nil); _date = State(initialValue: outing.date ?? Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("出门名称", text: $outing.title)
                Toggle("设置出发时间", isOn: $hasDate)
                if hasDate { DatePicker("出发", selection: $date) }
                Text("修改出发时间会保留已确认状态；已设置的提醒时间不会自动变更，请返回清单检查提醒。 ").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("编辑出门").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { outing.date = hasDate ? date : nil; outing.title = outing.title.trimmingCharacters(in: .whitespacesAndNewlines); store.update(outing); dismiss() }.disabled(outing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}


private struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: PackingItem
    let members: [FamilyMember]
    let onSave: (PackingItem) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("事项名称", text: $item.title)
                Toggle("提前准备", isOn: $item.needsPreparation)
                Toggle("临走携带", isOn: $item.needsCarrying)
                Section("本机分工") {
                    Picker("准备人", selection: $item.preparerID) { Text("未指定").tag(nil as UUID?); ForEach(members) { Text($0.name).tag($0.id as UUID?) } }
                    Picker("携带人", selection: $item.carrierID) { Text("未指定").tag(nil as UUID?); ForEach(members) { Text($0.name).tag($0.id as UUID?) } }
                    Text("分工只保存在本机，不会通知或同步给家人。 ").font(.footnote).foregroundStyle(.secondary)
                }
                Text("关闭某个阶段后，其原有确认状态会保留，重新开启时可以继续查看。 ").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("编辑事项").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines); onSave(item); dismiss() }.disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!item.needsPreparation && !item.needsCarrying)) }
            }
        }
    }
}

private struct ReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    let outing: Outing
    @State private var date: Date
    @State private var error: String?
    @State private var saving = false
    init(store: Store, outing: Outing) {
        self.store = store; self.outing = outing
        _date = State(initialValue: outing.reminderDate ?? outing.date ?? Date().addingTimeInterval(3600))
    }
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("提醒时间", selection: $date, in: Date()...)
                Text("通知默认不显示清单详情。提醒送达受系统通知设置影响，收到提醒不代表物品已带走。 ").font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                if outing.reminderDate != nil { Button("取消这条提醒", role: .destructive) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [outing.id.uuidString]); var updated = outing; updated.reminderDate = nil; store.update(updated); dismiss() } }
            }.navigationTitle("出门提醒").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await schedule() } }.disabled(saving) }
            }
        }
    }
    @MainActor private func schedule() async {
        guard date > Date() else { error = "请选择未来的时间。"; return }
        saving = true
        defer { saving = false }
        do {
            let center = UNUserNotificationCenter.current()
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard allowed else { error = "通知未获允许，请在系统设置中开启后重试。"; return }
            let content = UNMutableNotificationContent()
            content.title = "ReadyGo"
            content.body = "你有一项出门准备需要查看。"
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let request = UNNotificationRequest(identifier: outing.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try await center.add(request)
            var updated = outing; updated.reminderDate = date; store.update(updated); dismiss()
        } catch { self.error = "无法设置提醒，请稍后重试。" }
    }
}

private struct FamilyView: View {
    @ObservedObject var store: Store
    @State private var showingAdd = false
    @State private var deleting: FamilyMember?
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("一起准备，从容出发", systemImage: "person.2.fill").font(.headline).foregroundStyle(Palette.green)
                    Text("添加本机成员档案后，可在事项编辑页分别指定准备人和携带人。 ").font(.subheadline)
                    Text("这是本机分工记录，不会发送邀请或同步到家人的设备。 ").font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section("成员档案") {
                if store.members.isEmpty { Text("还没有成员，先添加一位吧。").foregroundStyle(.secondary) }
                ForEach(store.members) { member in
                    HStack { Image(systemName: "person.crop.circle.fill").foregroundStyle(Palette.green); Text(member.name); Spacer() }
                        .swipeActions { Button("删除", role: .destructive) { deleting = member } }
                }
                Button { showingAdd = true } label: { Label("添加成员", systemImage: "plus.circle") }
            }
            Section("家庭事项") {
                let assigned = store.outings.flatMap { outing in outing.items.filter { $0.preparerID != nil || $0.carrierID != nil }.map { (outing.id, outing.title, $0) } }
                if assigned.isEmpty { Text("还没有分工事项。打开清单中的事项即可设置。 ").foregroundStyle(.secondary) }
                ForEach(assigned, id: \.2.id) { outingID, title, item in
                    NavigationLink { OutingDetail(store: store, id: outingID) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline)
                            Text(title + " · 准备：" + store.memberName(item.preparerID) + " · 携带：" + store.memberName(item.carrierID)).font(.caption).foregroundStyle(.secondary)
                            Text((item.prepared ? "已准备" : "待准备") + " · " + (item.skipped ? "本次不带" : item.carried ? "已带走" : "待携带")).font(.caption).foregroundStyle(Palette.green)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.scrollContentBackground(.hidden).background(GlassBackdrop()).navigationTitle("家庭")
            .sheet(isPresented: $showingAdd) { AddMemberView(store: store) }
            .alert("删除成员档案？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) { if let member = deleting { store.removeMember(member.id) }; deleting = nil }
            } message: { Text("相关事项会保留，但该成员的分工会被清除。") }
    }
}
private struct AddMemberView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("例如：爸爸、妈妈", text: $name)
                Text("仅需一个称呼；请避免输入不必要的个人资料。 ").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("添加成员").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { store.members.append(FamilyMember(name: name.trimmingCharacters(in: .whitespacesAndNewlines))); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}

private struct DeviceView: View {
    var body: some View {
        ZStack {
            GlassBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("READYGO DEVICE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Palette.green)
                        Text("门口，多一份提醒。 ").font(.largeTitle.weight(.semibold))
                        Text("为出发前的最后一步，留一处清晰的提示。 ").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            Image(systemName: "display").font(.system(size: 38, weight: .light)).foregroundStyle(Palette.green)
                            Spacer()
                            Text("规划中").font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.55), in: Capsule())
                        }
                        Text("ReadyGo 门口提醒终端").font(.title2.weight(.semibold))
                        Text("计划支持接近亮屏、公共清单、触控确认和声光提示。 ").font(.subheadline).foregroundStyle(.secondary)
                        Divider()
                        HStack { Label("尚未连接设备", systemImage: "circle.dotted"); Spacer(); Text("未开放配对").foregroundStyle(.secondary) }.font(.footnote)
                    }.frame(maxWidth: .infinity, alignment: .leading).softCard()
                    NavigationLink { DeviceDetailView() } label: { HStack { Text("了解终端与购买信息"); Spacer(); Image(systemName: "arrow.up.right") }.font(.headline).foregroundStyle(Palette.ink).frame(maxWidth: .infinity).softCard() }.buttonStyle(.plain)
                    Text("终端尚未销售，实际功能、上市时间及服务范围以正式发布为准。 ").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
        }.foregroundStyle(Palette.ink).navigationTitle("设备").navigationBarTitleDisplayMode(.inline)
    }
}
private struct DeviceDetailView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("门口提醒终端").font(.title2.weight(.semibold))
                    Text("拟售 ¥199 / 台").font(.title3.weight(.semibold)).foregroundStyle(Palette.green)
                    Text("产品规划 · 尚未开放购买").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section("计划提供") {
                Label("接近亮屏与公共短清单", systemImage: "display")
                Label("触控确认、提示音与灯光", systemImage: "hand.tap")
                Label("缓存最近清单，离线显示同步时间", systemImage: "wifi.slash")
            }
            Section("购买前了解") {
                Text("终端与家庭会员分别购买，设备价格不包含会员；不买设备也可使用软件基础流程。")
                Text("计划使用 USB 供电，随附 USB 供电线，不含交流电源适配器，需自备合规 5V USB 电源。")
                Text("首批规划不含摄像头、录音麦克风、内置电池或整套置物架；不承诺声纹和远场语音。")
                Text("接近只代表有人靠近，不用于自动判断身份或自动确认已带走。私人事项不会主动显示在公共屏幕。")
            }
            Section("购买与连接") {
                Label("购买渠道尚未开放", systemImage: "cart")
                Text("待产品验收及销售渠道确定后提供购买链接、安装、退换与服务说明。当前不能下单或配对。 ").font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(GlassBackdrop()).navigationTitle("终端详情").navigationBarTitleDisplayMode(.inline)
    }
}
private struct MembershipView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("让重复准备更轻松").font(.title2.weight(.semibold))
                    Text("家庭会员与免费体验").foregroundStyle(.secondary)
                    Text("方案规划中，尚未开放订阅或自动执行体验。 ").font(.footnote).foregroundStyle(Palette.green)
                }.padding(.vertical, 8)
            }
            Section("免费使用 · ¥0") {
                Text("手动清单、常用模板、基础提醒、家庭分工、准备与携带确认及隐私设置。")
                Text("计划每家庭每月提供 3 次自动执行体验；该体验尚未开放。 ").font(.footnote).foregroundStyle(.secondary)
            }
            Section("家庭会员 · 计划 ¥99 / 年") {
                Text("同一家庭最多 6 个成员档案共用，计划每月 30 次自动执行。")
                Text("自动执行包括行程变更关联更新、多人清单合并和准备方案复用，结果由用户审阅确认。")
                Text("计划另提供 ¥9.9 / 月短期权益。订阅、计费与权益均未接通。 ").font(.footnote).foregroundStyle(.secondary)
            }
            Section("首轮体验计划") {
                Text("计划于 2027 年向最多 300 户提供首年 ¥79 的体验价格，期满如续费为 ¥99 / 年，不默认自动扣款。此为计划，尚未开始销售。")
            }
            Section("到期与设备费用") {
                Text("计划到期后停止新增高级自动执行，基础清单、已有提醒、查看与数据管理继续保留。")
                Text("门口终端拟售 ¥199 / 台，与会员分开购买，不包含会员。")
                NavigationLink("查看门口终端") { DeviceDetailView() }
            }
        }.scrollContentBackground(.hidden).background(GlassBackdrop()).navigationTitle("会员与费用").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: Store
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Palette.green)
                    VStack(alignment: .leading, spacing: 4) { Text("你好，出门搭子").font(.headline); Text("本机使用 · 无需登录").font(.subheadline).foregroundStyle(.secondary) }
                }.padding(.vertical, 6)
            }
            Section("会员与设备") {
                NavigationLink { MembershipView() } label: { Label("会员、费用与免费体验", systemImage: "sparkles.rectangle.stack") }
                NavigationLink { DeviceDetailView() } label: { Label("门口终端介绍与购买", systemImage: "display") }
            }
            Section("使用指南") {
                NavigationLink("如何记录与确认") { HelpView() }
                NavigationLink("提醒与通知") { NotificationHelpView() }
            }
            Section("隐私与数据") {
                NavigationLink("数据保存与隐私") { PrivacyView(store: store) }
            }
            Section("关于 ReadyGo") {
                Label("出门前，安心一点", systemImage: "leaf")
                LabeledContent("版本", value: "本地体验版")
            }
        }.scrollContentBackground(.hidden).background(GlassBackdrop()).navigationTitle("我的")
    }
}
private struct HelpView: View {
    var body: some View {
        List {
            Section("随时记录") { Text("在首页点“记一件事”，可以先存到随手记，也可以选择已有的出门安排。") }
            Section("准备与携带") { Text("提前准备和临走携带分别确认。点按已确认的状态可以撤销；本次不带只影响这次清单。") }
            Section("模板") { Text("新建出门时可选择模板。模板里的物品只是起点，可以按需编辑或删除。") }
            Section("家庭") { Text("可添加本机成员档案并为事项指定准备人、携带人；当前不支持多人同步。") }
        }.navigationTitle("使用指南")
    }
}
private struct NotificationHelpView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section("设置提醒") { Text("进入某次出门的详情，选择“设置出门提醒”，选择具体时间并允许系统通知。") }
            Section("查看权限") {
                Text("如果没有收到提醒，请检查系统通知权限和设备设置。通知内容默认隐藏清单详情。")
                Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            Section { Text("修改出发时间不会自动修改已有提醒，请在出门详情中手动检查。 ").foregroundStyle(.secondary) }
        }.navigationTitle("提醒与通知")
    }
}
private struct PrivacyView: View {
    @ObservedObject var store: Store
    @State private var confirmDelete = false
    var body: some View {
        List {
            Section("本地数据") { Text("当前版本无需登录，清单保存在本设备。删除 App 可能同时删除本地数据；目前尚不支持云同步。") }
            Section("导出数据") {
                if let data = try? JSONEncoder().encode(ExportData(outings: store.outings, members: store.members)), let json = String(data: data, encoding: .utf8) { ShareLink(item: json, subject: Text("ReadyGo 数据备份")) { Label("分享数据副本", systemImage: "square.and.arrow.up") }; Text("副本包含清单与本机成员称呼，请只分享给信任的接收方。 ").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("共享") { Text("家庭分工仅存在本机，尚不支持跨设备共享，也不会读取聊天内容。") }
            Section { Button("删除全部本机数据", role: .destructive) { confirmDelete = true } }
            Section("通知") { Text("通知由你主动设置，默认不显示清单详情。") }
        }.navigationTitle("数据与隐私").alert("删除全部本机数据？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: store.outings.map { $0.id.uuidString }); store.outings = []; store.members = [] }
        } message: { Text("所有出门、事项、成员档案和待发送提醒都会被删除，无法撤销。") }
    }
}
private struct ExportData: Codable { var outings: [Outing]; var members: [FamilyMember] }

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
