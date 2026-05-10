import Foundation
import Observation

struct ResumeProfile {
    var fullName: String = ""
    var city: String = ""
    var phone: String = ""
    var email: String = ""
    var linkedin: String = ""
    var github: String = ""
    var website: String = ""
    var educationBlock: String = ""
    var skillsBlock: String = ""

    var resumeAddress1: String {
        [city, phone, email].filter { !$0.trimmed.isEmpty }.joined(separator: " \\\\ ")
    }

    var resumeAddress2: String {
        [linkedin, github, website].filter { !$0.trimmed.isEmpty }.joined(separator: " \\\\ ")
    }

    var coverLetterAddress: String {
        [city, email, phone].filter { !$0.trimmed.isEmpty }.joined(separator: " \\\\ ")
    }

    func applying(to text: String) -> String {
        text
            .replacingOccurrences(of: "{{APPLYKIT_NAME}}", with: fullName)
            .replacingOccurrences(of: "{{APPLYKIT_ADDRESS_1}}", with: resumeAddress1)
            .replacingOccurrences(of: "{{APPLYKIT_ADDRESS_2}}", with: resumeAddress2)
            .replacingOccurrences(of: "{{APPLYKIT_COVER_ADDRESS}}", with: coverLetterAddress)
            .replacingOccurrences(of: "{{APPLYKIT_EDUCATION}}", with: educationBlock)
            .replacingOccurrences(of: "{{APPLYKIT_SKILLS}}", with: skillsBlock)
    }
}

@Observable final class AppDataStore {
    var applications:    [JobApplication]    = []
    var experiences:     [ExperienceBullet]  = []
    var employments:     [Employment]        = []
    var documents:       [GeneratedDocument] = []
    var promptTemplates: [PromptTemplate]    = []
    var aiRuns:          [AIRun]             = []
    var profile:         ResumeProfile       = ResumeProfile()
}
