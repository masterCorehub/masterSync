package com.nexus.mastersync.ui

import com.nexus.mastersync.ui.onboarding.OnboardingPage
import com.nexus.mastersync.ui.onboarding.Onboarding
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingTest {
    @Test fun pagesRunWelcomeMacPairFeatures() {
        assertEquals(listOf(OnboardingPage.Welcome, OnboardingPage.Mac, OnboardingPage.Pair, OnboardingPage.Features),
            OnboardingPage.entries.toList())
        assertEquals(OnboardingPage.Mac, OnboardingPage.Welcome.next)
        assertNull(OnboardingPage.Features.next)
        assertNull(OnboardingPage.Welcome.previous)
        assertEquals(OnboardingPage.Pair, OnboardingPage.Features.previous)
        assertTrue(OnboardingPage.Features.isLast)
        assertEquals("1 de 4", OnboardingPage.Welcome.position)
        assertEquals("4 de 4", OnboardingPage.Features.position)
    }

    @Test fun showsOnlyOnFirstRunWithoutAPairedMac() {
        assertTrue(Onboarding.shouldShow(done = false, hasPairedMac = false))
        assertFalse(Onboarding.shouldShow(done = true, hasPairedMac = false))
        assertFalse(Onboarding.shouldShow(done = false, hasPairedMac = true))
    }

    @Test fun pairPageAdvancesByItselfWhenAMacConnects() {
        assertTrue(Onboarding.canContinue(OnboardingPage.Pair, connected = true))
        assertFalse(Onboarding.canContinue(OnboardingPage.Pair, connected = false))
        assertTrue(Onboarding.canContinue(OnboardingPage.Welcome, connected = false))
    }

    @Test fun everyPageHasCopy() {
        OnboardingPage.entries.forEach {
            assertTrue(it.title.isNotBlank()); assertTrue(it.body.isNotBlank())
        }
    }
}
