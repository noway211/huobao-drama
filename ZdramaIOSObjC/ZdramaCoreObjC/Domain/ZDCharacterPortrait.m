#import "ZDCharacterPortrait.h"

NSString * const ZDCharacterTurnaroundSize = @"1536x1024";

NSString *ZDCharacterPortraitPrompt(ZDCharacter *character) {
    NSString *appearance = [character.appearance stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *description = [character.characterDescription stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *detail = appearance.length ? appearance : (description.length ? description : @"character portrait");
    return [NSString stringWithFormat:@"%@, %@, character turnaround sheet, front view, side view, and back view side by side, full body, high quality", character.name ?: @"", detail];
}
