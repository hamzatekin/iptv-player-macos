import Testing
@testable import IPTVCore

@Suite struct LogRedactionTests {
    @Test(arguments: [
        ("Failed to open http://h:8080/live/demo/s3cret/42.ts.\n", "Failed to open http://h:8080/live/***/***/42.ts.\n"),
        ("http://h/player_api.php?username=demo&password=s3cret&action=x", "http://h/player_api.php?username=***&password=***&action=x"),
        ("Redirect to http://1.2.3.4/demo/s3cret/42", "Redirect to http://1.2.3.4/***/***/42"),
        ("p%40ss in an encoded URL", "*** in an encoded URL"),
        ("[ffmpeg] Connection timed out\n", "[ffmpeg] Connection timed out\n"),
    ])
    func hidesLogins(line: String, expected: String) {
        #expect(LogRedaction.redact(line, hiding: ["demo", "s3cret", "p@ss", ""]) == expected)
    }

    @Test(arguments: [
        // The username inside the password, both orders of the secrets list.
        (["viewer", "viewer123"], "Redirect to http://1.2.3.4/viewer/viewer123/42", "Redirect to http://1.2.3.4/***/***/42"),
        (["viewer123", "viewer"], "Redirect to http://1.2.3.4/viewer/viewer123/42", "Redirect to http://1.2.3.4/***/***/42"),
        // URL.appending(path:) keeps "@" and encodes the space.
        (["u", "p@ss word"], "http://h/x/p@ss%20word/42.ts", "http://h/x/***/42.ts"),
    ])
    func hidesOverlappingAndPathEncodedSecrets(secrets: [String], line: String, expected: String) {
        #expect(LogRedaction.redact(line, hiding: secrets) == expected)
    }
}
