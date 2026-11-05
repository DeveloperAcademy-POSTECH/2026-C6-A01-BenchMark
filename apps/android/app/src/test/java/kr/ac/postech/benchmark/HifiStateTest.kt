package kr.ac.postech.benchmark

import androidx.lifecycle.SavedStateHandle
import org.junit.Assert.*
import org.junit.Test

class HifiStateTest {
    @Test fun limitsPreserveUnicodeAndAmountBoundary() {
        val text = "😀".repeat(31)
        val result = boundedText(text, 30)
        assertEquals(30, result.codePointCount(0, result.length))
        assertFalse(Character.isHighSurrogate(result.last()))
        assertFalse(validAmount("49999")); assertTrue(validAmount("50000"))
        assertFalse(validAmount("999999999999999999999"))
    }
    @Test fun sortingUsesDatesAndLocalReactions() {
        val newest = Donation(1, 1, "50000", Story(), createdDate = "2026-10-09")
        val oldest = Donation(5, 1, "50000", Story(), createdDate = "2026-04-26", reactions = 2)
        val state = LofiState(donations = listOf(oldest, newest))
        assertEquals(listOf(1, 5), sortedDonations(state).map { it.id })
        assertEquals(listOf(5, 1), sortedDonations(state.copy(donationSort = "오래된순")).map { it.id })
        assertEquals(listOf(5, 1), sortedDonations(state.copy(donationSort = "좋아요순")).map { it.id })
    }
    @Test fun layoutAndDraftRestoreAndNewApplicationResetsConsent() {
        val saved = SavedStateHandle()
        val model = LofiModel(saved)
        model.update { it.copy(gridDonations = true, donationSort = "오래된순", amount = "50000",
            draft = Story("기억", "마음"), pledgeDate = "2026-10-16", requiredTerms = true,
            receiptTerms = true, honorTerms = true, thirdPartyTerms = true) }
        val restored = LofiModel(saved)
        assertEquals(model.state, restored.state)
        restored.startDonation()
        assertTrue(restored.state.gridDonations)
        assertEquals("", restored.state.pledgeDate)
        assertFalse(restored.state.requiredTerms || restored.state.receiptTerms || restored.state.honorTerms || restored.state.thirdPartyTerms)
    }
    @Test fun localLikesToggleWithoutNegativeCounts() {
        val model = LofiModel(SavedStateHandle())
        model.loadExample()
        val id = model.state.donations.first().id
        model.toggleLike(id); assertEquals(1, model.state.donations.first().reactions)
        model.toggleLike(id); assertEquals(0, model.state.donations.first().reactions)
        assertFalse(model.state.donations.first().liked)
    }
}
