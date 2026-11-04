import Testing
import Foundation
@testable import MarkShotCore
@Test func reversedRectangle() { #expect(Geometry.rect(CGPoint(x: 20,y: 30),CGPoint(x: 3,y: 5)) == CGRect(x:3,y:5,width:17,height:25)) }
@Test func cropOutside() { #expect(Geometry.crop(CGRect(x:200,y:200,width:10,height:10),in:CGSize(width:100,height:100)) == nil) }
@Test func cropClipsEdges() { #expect(Geometry.crop(CGRect(x:-10,y:-10,width:40,height:40),in:CGSize(width:100,height:100)) == CGRect(x:0,y:0,width:30,height:30)) }
@Test func cropRejectsTiny() { #expect(Geometry.crop(CGRect(x:0,y:0,width:1,height:1),in:CGSize(width:100,height:100)) == nil) }
@Test func cropRoundsPixels() { #expect(Geometry.crop(CGRect(x:2.2,y:3.5,width:4,height:5),in:CGSize(width:100,height:100)) == CGRect(x:2,y:3,width:5,height:6)) }
@Test func retinaMapping() { #expect(Geometry.imagePoint(CGPoint(x:100,y:50),image:CGSize(width:2000,height:1000),view:CGSize(width:1000,height:500)) == CGPoint(x:200,y:100)) }
@Test func pointClamping() { #expect(Geometry.clamp(CGPoint(x:-5,y:120),to:CGSize(width:100,height:100)) == CGPoint(x:0,y:100)) }
@Test func zeroView() { #expect(Geometry.imagePoint(CGPoint(x:1,y:1),image:CGSize(width:100,height:100),view:.zero) == .zero) }
@Test func arrowDirection() { let h=Geometry.arrowHead(start:.zero,end:CGPoint(x:100,y:0)); #expect(h.count == 3); #expect(h[0].x < 100); #expect(h[0].y > 0); #expect(h[2].y < 0) }
@Test func arrowVertical() { let h=Geometry.arrowHead(start:.zero,end:CGPoint(x:0,y:100)); #expect(h[0].y < 100); #expect(h[2].y < 100) }
@Test func stepsIgnoreOtherTools() { #expect(Geometry.nextStep([Mark(.text,.zero,.zero,number:50),Mark(.step,.zero,.zero,number:3)]) == 4) }
@Test func firstStep() { #expect(Geometry.nextStep([]) == 1) }
@Test func blankTextRejected() { #expect(!Geometry.valid(Mark(.text,.zero,.zero,text:" \n "))) }
@Test func textAccepted() { #expect(Geometry.valid(Mark(.text,.zero,.zero,text:"Read this"))) }
@Test func zeroDragRejected() { #expect(!Geometry.valid(Mark(.arrow,.zero,.zero))) }
@Test func stepClickAccepted() { #expect(Geometry.valid(Mark(.step,.zero,.zero))) }
@Test func undoRedo() { var h=Timeline(1);h.commit(2);h.commit(3);h.undo();#expect(h.current==2);h.redo();#expect(h.current==3) }
@Test func editsClearRedo() { var h=Timeline(1);h.commit(2);h.undo();h.commit(4);#expect(h.redoItems.isEmpty);h.redo();#expect(h.current==4) }
@Test func emptyUndoSafe() { var h=Timeline(1);h.undo();h.redo();#expect(h.current==1) }
@Test func recentLimit() { #expect(Recent.adding(12,to:Array(1...11)).count==10) }
@Test func recentMovesExistingToFront() { #expect(Recent.adding(2,to:[1,2,3]) == [2,1,3]) }
@Test func zeroHistoryLimit() { #expect(Recent.adding(2,to:[1],limit:0).isEmpty) }
@Test func exportFilename() { #expect(Geometry.filename(date:Date(timeIntervalSince1970:0),id:UUID(uuidString:"12345678-1234-1234-1234-123456789ABC")!) == "MarkShot-1970-01-01-000000-12345678.png") }
@Test func undoBounded() { var h=Timeline(0);for n in 1...50 {h.commit(n)};#expect(h.undoItems.count==40) }
