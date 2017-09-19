/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCGLogger
import Deferred
import Shared

public let NotificationDatabaseWasRecreated = Notification.Name("NotificationDatabaseWasRecreated")

private let log = Logger.syncLogger

public typealias Args = [Any?]

open class BrowserDB {
    fileprivate let db: SwiftData

    // SQLITE_MAX_VARIABLE_NUMBER = 999 by default. This controls how many ?s can
    // appear in a query string.
    open static let MaxVariableNumber = 999

    public init(filename: String, secretKey: String? = nil, schema: Schema, files: FileAccessor) {
        log.debug("Initializing BrowserDB: \(filename).")

        let file = URL(fileURLWithPath: (try! files.getAndEnsureDirectory())).appendingPathComponent(filename).path

        if AppConstants.BuildChannel == .developer && secretKey != nil {
            log.debug("Will attempt to use encrypted DB: \(file) with secret = \(secretKey ?? "nil")")
        }

        self.db = SwiftData(filename: file, key: secretKey, prevKey: nil, schema: schema, files: files)
    }

    // For testing purposes or other cases where we want to ensure that this `BrowserDB`
    // instance has been initialized (schema is created/updated).
    public func touch() -> Success {
        let deferred = Success()

        do {
            try withConnection { connection -> Void in
                guard let _ = connection as? ConcreteSQLiteDBConnection else {
                    throw DatabaseError(description: "Could not establish a database connection")
                }

                deferred.fill(Maybe(success: ()))
            }
        } catch let err as NSError {
            deferred.fill(Maybe(failure: err))
        }

        return deferred
    }

    @discardableResult func withConnection<T>(flags: SwiftData.Flags = .readWriteCreate, _ callback: @escaping (_ connection: SQLiteDBConnection) throws -> T) throws -> T {
        var res: T!

        if let err = db.withConnection(flags, cb: { connection -> NSError? in
            do {
                res = try callback(connection)
            } catch let err as NSError {
                return err
            }
            
            return nil
        }) {
            throw err
        }

        return res
    }

    func transaction(synchronous: Bool = true, _ callback: @escaping (_ connection: SQLiteDBConnection) throws -> Bool) -> NSError? {
        return db.transaction(synchronous: synchronous) { connection in
            return try callback(connection)
        }
    }

    func vacuum() {
        log.debug("Vacuuming a BrowserDB.")
        _ = db.withConnection(SwiftData.Flags.readWriteCreate, synchronous: true) { connection in
            return connection.vacuum()
        }
    }

    func checkpoint() {
        log.debug("Checkpointing a BrowserDB.")
        _ = db.transaction(synchronous: true) { connection in
            connection.checkpoint()
            return true
        }
    }

    public class func varlist(_ count: Int) -> String {
        return "(" + Array(repeating: "?", count: count).joined(separator: ", ") + ")"
    }

    enum InsertOperation: String {
        case Insert = "INSERT"
        case Replace = "REPLACE"
        case InsertOrIgnore = "INSERT OR IGNORE"
        case InsertOrReplace = "INSERT OR REPLACE"
        case InsertOrRollback = "INSERT OR ROLLBACK"
        case InsertOrAbort = "INSERT OR ABORT"
        case InsertOrFail = "INSERT OR FAIL"
    }

    /**
     * Insert multiple sets of values into the given table.
     *
     * Assumptions:
     * 1. The table exists and contains the provided columns.
     * 2. Every item in `values` is the same length.
     * 3. That length is the same as the length of `columns`.
     * 4. Every value in each element of `values` is non-nil.
     *
     * If there are too many items to insert, multiple individual queries will run
     * in sequence.
     *
     * A failure anywhere in the sequence will cause immediate return of failure, but
     * will not roll back — use a transaction if you need one.
     */
    func bulkInsert(_ table: String, op: InsertOperation, columns: [String], values: [Args]) -> Success {
        // Note that there's a limit to how many ?s can be in a single query!
        // So here we execute 999 / (columns * rows) insertions per query.
        // Note that we can't use variables for the column names, so those don't affect the count.
        if values.isEmpty {
            log.debug("No values to insert.")
            return succeed()
        }

        let variablesPerRow = columns.count

        // Sanity check.
        assert(values[0].count == variablesPerRow)

        let cols = columns.joined(separator: ", ")
        let queryStart = "\(op.rawValue) INTO \(table) (\(cols)) VALUES "

        let varString = BrowserDB.varlist(variablesPerRow)

        let insertChunk: ([Args]) -> Success = { vals -> Success in
            let valuesString = Array(repeating: varString, count: vals.count).joined(separator: ", ")
            let args: Args = vals.flatMap { $0 }
            return self.run(queryStart + valuesString, withArgs: args)
        }

        let rowCount = values.count
        if (variablesPerRow * rowCount) < BrowserDB.MaxVariableNumber {
            return insertChunk(values)
        }

        log.debug("Splitting bulk insert across multiple runs. I hope you started a transaction!")
        let rowsPerInsert = (999 / variablesPerRow)
        let chunks = chunk(values, by: rowsPerInsert)
        log.debug("Inserting in \(chunks.count) chunks.")

        // There's no real reason why we can't pass the ArraySlice here, except that I don't
        // want to keep fighting Swift.
        return walk(chunks, f: { insertChunk(Array($0)) })
    }

    func runWithConnection<T>(_ block: @escaping (_ connection: SQLiteDBConnection, _ err: inout NSError?) -> T) -> Deferred<Maybe<T>> {
        return DeferredDBOperation(db: self.db, block: block).start()
    }

    func write(_ sql: String, withArgs args: Args? = nil) -> Deferred<Maybe<Int>> {
        return self.runWithConnection() { (connection, err) -> Int in
            err = connection.executeChange(sql, withArgs: args)
            if err == nil {
                let modified = connection.numberOfRowsModified
                log.debug("Modified rows: \(modified).")
                return modified
            }
            return 0
        }
    }

    public func forceClose() {
        db.forceClose()
    }

    public func reopenIfClosed() {
        db.reopenIfClosed()
    }

    func run(_ sql: String, withArgs args: Args? = nil) -> Success {
        return run([(sql, args)])
    }

    func run(_ commands: [String]) -> Success {
        return self.run(commands.map { (sql: $0, args: nil) })
    }

    /**
     * Runs an array of SQL commands. Note: These will all run in order in a transaction and will block
     * the caller's thread until they've finished. If any of them fail the operation will abort (no more
     * commands will be run) and the transaction will roll back, returning a DatabaseError.
     */
    func run(_ commands: [(sql: String, args: Args?)]) -> Success {
        if commands.isEmpty {
            return succeed()
        }

        if let err = self.transaction({ conn -> Bool in
            for (sql, args) in commands {
                if let err = conn.executeChange(sql, withArgs: args) {
                    log.warning("SQL operation failed: \(err.localizedDescription)")
                    throw err
                }
            }
            return true
        }) {
            return deferMaybe(DatabaseError(err: err))
        }

        return succeed()
    }

    func runAsync(_ commands: [(sql: String, args: Args?)]) -> Success {
        if commands.isEmpty {
            return succeed()
        }

        let deferred = Success()

        if let err = self.transaction(synchronous: false, { (conn) -> Bool in
            for (sql, args) in commands {
                if let err = conn.executeChange(sql, withArgs: args) {
                    log.warning("SQL operation failed: \(err.localizedDescription)")
                    throw err
                }
            }

            deferred.fill(Maybe(success: ()))
            return true
        }) {
            deferred.fill(Maybe(failure: DatabaseError(err: err)))
        }

        return deferred
    }

    func runQuery<T>(_ sql: String, args: Args?, factory: @escaping (SDRow) -> T) -> Deferred<Maybe<Cursor<T>>> {
        return runWithConnection { (connection, _) -> Cursor<T> in
            return connection.executeQuery(sql, factory: factory, withArgs: args)
        }
    }

    func queryReturnsResults(_ sql: String, args: Args? = nil) -> Deferred<Maybe<Bool>> {
        return self.runQuery(sql, args: args, factory: { _ in true })
         >>== { deferMaybe($0[0] ?? false) }
    }

    func queryReturnsNoResults(_ sql: String, args: Args? = nil) -> Deferred<Maybe<Bool>> {
        return self.runQuery(sql, args: nil, factory: { _ in false })
          >>== { deferMaybe($0[0] ?? true) }
    }
}
