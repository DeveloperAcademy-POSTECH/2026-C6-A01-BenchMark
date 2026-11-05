import SwiftUI

/// Public search metadata is entered by its owner; certification evidence is never copied here.
struct OiPublicAcademicEditor: View {
    let remote: OiRemoteStore
    let owner: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var info: OiPublicAcademicInfo
    @State private var saveError: String?
    @State private var saving = false

    init(remote: OiRemoteStore, owner: UUID) {
        self.remote = remote
        self.owner = owner
        let profile = remote.profile
        _info = State(initialValue: OiPublicAcademicInfo(name: profile?.publicName ?? "",
            department: profile?.department ?? "", admissionYear: profile?.admissionYear ?? ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름", text: $info.name)
                        .accessibilityIdentifier("my.settings.academic.name")
                    TextField("학과", text: $info.department)
                        .accessibilityIdentifier("my.settings.academic.department")
                    TextField("학번 (입학연도, 예: 26 또는 2026)", text: $info.admissionYear)
                        .keyboardType(.numberPad).accessibilityIdentifier("my.settings.academic.year")
                } footer: {
                    Text("입력한 이름·학과·입학연도는 공개 이야기의 기부자 검색에 사용됩니다. 전체 학생번호를 입력하지 마세요. 학교는 설정의 학적정보에서 선택할 수 있습니다. 빈칸으로 저장하면 해당 정보를 지웁니다.")
                }
                if !info.cleaned.isValid {
                    Text("이름은 50자, 학과는 100자 이내로 입력해주세요. 학번은 두 자리 또는 네 자리 입학연도로 입력해주세요.")
                        .foregroundStyle(.red)
                }
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .navigationTitle("기부자 검색 정보").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(saving || remote.isBusy || !info.cleaned.isValid || remote.account?.id != owner)
                }
            }
            .interactiveDismissDisabled(saving)
            .onChange(of: remote.account?.id) { _, id in if id != owner { dismiss() } }
        }
    }

    @MainActor private func save() async {
        guard !saving, remote.account?.id == owner else { return }
        saving = true; saveError = nil
        defer { saving = false }
        await remote.updateProfile(academicInfo: info.cleaned)
        guard remote.account?.id == owner else { return }
        if let error = remote.error { saveError = error } else { dismiss() }
    }
}
