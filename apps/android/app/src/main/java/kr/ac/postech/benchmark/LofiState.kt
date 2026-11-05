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
    BENCH("벤치 선택"), SUPPORT("후원"), STEPS("후원 단계"), CATEGORY("기부자 구분"), GUIDE("기부 안내"), TERMS("약관 동의"), VERIFY("본인인증"),
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
    val stage: Int = 0, val liked: Boolean = false, val reactions: Int = 0, val createdDate: String = ""
) : Parcelable

@Parcelize
data class LofiState(
    val donor: Donor = Donor(), val bench: Int = 1, val amount: String = "",
    val draft: Story = Story(), val requiredTerms: Boolean = false,
    val receiptTerms: Boolean = false, val donations: List<Donation> = emptyList(),
    val selectedDonation: Int = 0, val editDraft: Story = Story(),
    val reaction: String = "", val gridDonations: Boolean = false, val donationSort: String = "최신순",
    val pledgeDate: String = "", val honorTerms: Boolean = false, val thirdPartyTerms: Boolean = false,
    val onboardingComplete: Boolean = false
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
        it.copy(amount = "", draft = Story(), requiredTerms = false, receiptTerms = false,
            honorTerms = false, thirdPartyTerms = false, pledgeDate = "")
    }

    fun submitExample() {
        val id = (state.donations.maxOfOrNull { it.id } ?: 0) + 1
        val donation = Donation(id, state.bench, state.amount, state.draft,
            createdDate = java.time.LocalDate.now(java.time.ZoneId.of("Asia/Seoul")).toString())
        update { it.copy(donations = it.donations + donation, selectedDonation = id) }
    }

    fun loadExample() {
        val id = (state.donations.maxOfOrNull { it.id } ?: 0) + 1
        val stories = listOf(
            Story("작은 쉼", "함께했던 캠퍼스의 기억을 남깁니다.", 1),
            Story("생일을 축하해 준 친구들", "함께했던 생일의 기억을 남깁니다.", 2),
            Story("아카데미에서 바라본 풍경", "포스텍의 아름다운 풍경을 떠올리며.", 3),
            Story("지곡회관의 추억", "호수가 보이던 자리의 기억.", 4),
            Story("칠포 바다여행", "동기들과 함께했던 여름.", 5)
        )
        val dates = listOf("2026-10-09", "2026-09-02", "2026-08-07", "2026-06-29", "2026-04-26")
        val examples = stories.mapIndexed { index, story -> Donation(id + index, 1, "50000", story, 2, createdDate = dates[index]) }
        update { it.copy(donations = it.donations + examples, selectedDonation = id) }
    }

    fun toggleLike(id: Int) = update { current -> current.copy(donations = current.donations.map {
        if (it.id == id) it.copy(liked = !it.liked, reactions = (it.reactions + if (it.liked) -1 else 1).coerceAtLeast(0)) else it
    }) }

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

fun validAmount(value: String): Boolean = value.length in 1..12 && value.all { it in '0'..'9' } &&
    (value.toLongOrNull() ?: 0) >= 50_000
