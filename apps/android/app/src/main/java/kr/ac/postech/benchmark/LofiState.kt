package kr.ac.postech.benchmark

import android.os.Parcelable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import kotlinx.parcelize.Parcelize

enum class Screen(val title: String) {
    INTENT("기부자 정보"), ONBOARDING_PROFILE("인적 사항 작성"),
    ONBOARDING_VERIFY("본인인증"), HOME("BenchMark"), BENCHES("벤치 위치 확인"),
    BENCH("벤치 선택"), GUIDE("기부 안내"), TERMS("약관 동의"), VERIFY("본인인증"),
    AMOUNT("기부금 입력"), DONOR("인적사항 입력"), STORY("스토리 작성"),
    PHOTO("이미지 첨부"), REVIEW("결제 및 접수"), RECEIPT("접수 완료"),
    MY_DONATIONS("나의 기부"), DONATION("기부 스토리 상세"), EDIT("스토리 편집"),
    PREVIEW("스토리 미리보기"), PROGRESS("설치 프로세스"), INSTALLED("나의 기부 벤치"),
    NFC("NFC 벤치 체험"), PUBLIC_STORY("기부자의 이야기"), AR("AR 카메라"),
    PROFILE("프로필"), NOTIFICATIONS("알림")
}

@Parcelize
data class Donor(
    val category: String = "동문", val name: String = "", val phone: String = "",
    val email: String = "", val wantsReceipt: Boolean = false
) : Parcelable

@Parcelize
data class Story(val title: String = "", val body: String = "", val photo: Int = 0) : Parcelable

@Parcelize
data class Donation(
    val id: Int, val bench: Int, val amount: String, val story: Story,
    val stage: Int = 0
) : Parcelable

@Parcelize
data class LofiState(
    val donor: Donor = Donor(), val bench: Int = 1, val amount: String = "",
    val draft: Story = Story(), val requiredTerms: Boolean = false,
    val receiptTerms: Boolean = false, val donations: List<Donation> = emptyList(),
    val selectedDonation: Int = 0, val editDraft: Story = Story(),
    val reaction: String = ""
) : Parcelable

class LofiModel(private val saved: SavedStateHandle) : ViewModel() {
    var state by mutableStateOf(saved.get<LofiState>("lofi") ?: LofiState())
        private set

    val selectedDonation: Donation?
        get() = state.donations.firstOrNull { it.id == state.selectedDonation }

    fun update(transform: (LofiState) -> LofiState) {
        state = transform(state)
        saved["lofi"] = state
    }

    fun startDonation() = update {
        it.copy(amount = "", draft = Story(), requiredTerms = false, receiptTerms = false)
    }

    fun submitExample() {
        val id = (state.donations.maxOfOrNull { it.id } ?: 0) + 1
        val donation = Donation(id, state.bench, state.amount, state.draft)
        update { it.copy(donations = it.donations + donation, selectedDonation = id) }
    }

    fun loadExample() {
        val id = (state.donations.maxOfOrNull { it.id } ?: 0) + 1
        val donation = Donation(id, 1, "1000000", Story("작은 쉼", "함께했던 캠퍼스의 기억을 남깁니다.", 1), 2)
        update { it.copy(donations = it.donations + donation, selectedDonation = id) }
    }

    fun beginEdit() { selectedDonation?.let { donation -> update { it.copy(editDraft = donation.story) } } }

    fun saveEdit() = update { current ->
        current.copy(donations = current.donations.map {
            if (it.id == current.selectedDonation) it.copy(story = current.editDraft) else it
        })
    }

    fun reset() = update { LofiState() }
}

val donorCategories = listOf("동문", "재학생", "학부모", "교원", "직원", "연구원", "기업", "단체", "일반인")
val installationStages = listOf("접수", "내용 확인", "제작 준비", "명패 제작", "설치 준비", "설치 완료")

fun validAmount(value: String): Boolean = (value.toLongOrNull() ?: 0) >= 1_000_000
