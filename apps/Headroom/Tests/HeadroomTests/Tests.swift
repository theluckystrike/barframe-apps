import Testing
import Foundation
import CProbe
@testable import HeadroomModel
@Test func normalBudget() { #expect(Reading().capacity(budget:2)==5) }
@Test func reserveExceedsAvailable() { #expect(Reading(available:3).capacity(budget:2)==0) }
@Test func swapStopsNewAgents() { #expect(Reading(swap:0.0001).capacity(budget:2)==0) }
@Test func pressureStopsNewAgents() { for p in [0,2,4,8] { #expect(Reading(pressure:p).capacity(budget:2)==0) } }
@Test func unavailableMemory() { #expect(Reading(memoryOK:false).capacity(budget:2)==nil) }
@Test func invalidInputs() { for v in [0.0,-1,Double.nan,Double.infinity] { #expect(Reading().capacity(budget:v)==nil) }; #expect(Reading().capacity(budget:2,reserve:-1)==nil); #expect(Reading(available:.nan).capacity(budget:2)==nil) }
@Test func roundsDown() { #expect(Reading(available:9.9).capacity(budget:2)==2) }
@Test func residentIsNotBudget() { #expect(Reading(resident:999).capacity(budget:2)==Reading(resident:0).capacity(budget:2)) }
@Test func missingProcessesStillAllowsBudget() { #expect(Reading(processesOK:false).capacity(budget:2)==5) }
@Test func supportedNamesAreExact() { #expect(hr_agent("codex")==1); #expect(hr_agent("claude")==1); #expect(hr_agent("node")==0); #expect(hr_agent("my-codex-note")==0); #expect(hr_agent(nil)==0) }
@Test func liveMemoryProbes() { let r=Reading.live(); #expect(r.memoryOK); #expect(r.total>0); #expect(r.available>=0 && r.available<=r.total); #expect(r.compressed>=0 && r.compressed<=r.total); #expect(r.swap>=0); #expect([1,2,4].contains(r.pressure)) }
@Test func liveProcessProbe() { let r=Reading.live(); #expect(r.processesOK); #expect(r.agents>=0); #expect(r.resident>=0); #expect(r.unreadable>=0) }
@Test func sampleScenarios() { #expect(Reading.sample(1).capacity(budget:2)==0); #expect(Reading.sample(2).capacity(budget:4)==4) }
@Test func hugeInputsDoNotOverflow() { #expect(Reading(available:Double.greatestFiniteMagnitude).capacity(budget:0.5)==10000) }
