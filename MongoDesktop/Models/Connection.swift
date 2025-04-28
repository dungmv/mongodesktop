//
//  Connection.swift
//  mongoui
//
//  Created by Trae AI on 21/4/25.
//

import Foundation
import SwiftData

@Model
final class Connection {
    var name: String
    var host: String
    var port: Int
    var username: String?
    var password: String?
    var database: String?
    var authDatabase: String?
    var useSRV: Bool
    var useSSL: Bool
    var createdAt: Date
    var lastConnectedAt: Date?
    
    init(
        name: String,
        host: String,
        port: Int = 27017,
        username: String? = nil,
        password: String? = nil,
        database: String? = nil,
        authDatabase: String? = nil,
        useSRV: Bool = false,
        useSSL: Bool = false
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.authDatabase = authDatabase
        self.useSRV = useSRV
        self.useSSL = useSSL
        self.createdAt = Date()
    }
    
    var connectionString: String {
        var uri = "mongodb"
        
        if useSRV {
            uri += "+srv"
        }
        
        uri += "://"
        
        if let username = username, !username.isEmpty {
            uri += username
            
            if let password = password, !password.isEmpty {
                uri += ":(password)"
            }
            
            uri += "@"
        }
        
        uri += host
        
        if !useSRV && port != 27017 {
            uri += ":(port)"
        }
        
        if let database = database, !database.isEmpty {
            uri += "/(database)"
        }
        
        var queryParams: [String] = []
        
        if let authDatabase = authDatabase, !authDatabase.isEmpty {
            queryParams.append("authSource=(authDatabase)")
        }
        
        if useSSL {
            queryParams.append("ssl=true")
        }
        
        if !queryParams.isEmpty {
            uri += "?(queryParams.joined(separator: \"&\"))"
        }
        
        return uri
    }
}
