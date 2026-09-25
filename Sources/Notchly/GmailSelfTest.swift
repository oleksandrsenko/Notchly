import Foundation

/// `Notchly --imap-selftest`: проверка разбора писем и соединения с Gmail без настоящего аккаунта.
enum GmailSelfTest {
    static func run() {
        let headers = "From: =?UTF-8?B?0JjQstCw0L0g0J/QtdGC0YDQvtCy?= <ivan@example.com>\r\n"
            + "Subject: =?UTF-8?Q?=D0=9F=D1=80=D0=B8=D0=B2=D0=B5=D1=82?= =?UTF-8?Q?_=D0=BC=D0=B8=D1=80?=\r\n"
            + "Date: Fri, 25 Sep 2026 16:10:00 +0300\r\n\r\n"
        let body = Data(headers.utf8)
        var sample = Data("* 12 FETCH (X-GM-THRID 1790123456789 X-GM-MSGID 1790123456790 BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {\(body.count)}\r\n".utf8)
        sample.append(body)
        sample.append(Data(")\r\na4 OK Success\r\n".utf8))
        for m in GmailClient.parseFetch(sample) {
            print("parsed:", m.senderName, "|", m.senderEmail, "|", m.subject, "|", m.date, "|", m.threadHex)
        }
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                _ = try await GmailClient.fetchUnread(email: "selftest@gmail.com", password: "wrongpassword")
                print("login: unexpected success")
            } catch {
                print("login:", (error as? IMAPError)?.message ?? error.localizedDescription)
            }
            sem.signal()
        }
        sem.wait()
    }
}
