import Foundation

struct SQLiteTransactionExecutor {
    struct Operations {
        let begin: String
        let commit: String
        let rollback: String

        static let standard = Operations(
            begin: "begin transaction",
            commit: "commit transaction",
            rollback: "rollback transaction"
        )
    }

    private let operations: Operations
    private let execute: (_ sql: String, _ operation: String) -> Bool

    init(
        operations: Operations = .standard,
        execute: @escaping (_ sql: String, _ operation: String) -> Bool
    ) {
        self.operations = operations
        self.execute = execute
    }

    @discardableResult
    func perform(_ work: () -> Bool) -> Bool {
        guard execute("BEGIN IMMEDIATE TRANSACTION", operations.begin) else {
            return false
        }
        guard work() else {
            rollback()
            return false
        }
        guard execute("COMMIT", operations.commit) else {
            rollback()
            return false
        }
        return true
    }

    private func rollback() {
        _ = execute("ROLLBACK", operations.rollback)
    }
}
