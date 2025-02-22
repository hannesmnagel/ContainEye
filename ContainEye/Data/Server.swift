//
//  Server.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import Foundation
import NIO
@preconcurrency import Citadel
import KeychainAccess
import Foundation


@MainActor
@Observable
class Server: Identifiable, @preconcurrency Hashable {
    let id = UUID()
    let credential: Credential
    var cpuUsage = Double?.none
    var memoryUsage = Double?.none
    var diskUsage = Double?.none
    var networkUpstream = Double?.none
    var networkDownstream = Double?.none
    var swapUsage = Double?.none
    var systemLoad = Double?.none
    var ioWait = Double?.none
    var stealTime = Double?.none
    var uptime = Date?.none
    var lastUpdate: Date? = nil
    var containers: [Container] = []
    var errors = Set<ServerError>()
    var updatesPaused = true
    var dockerUpdatesPaused = true
    var isConnected = false

    init(credential: Credential) {
        self.credential = credential

        Task {
            await update()
        }
    }

    func update() async {
        if !updatesPaused {
            await fetchServerStats()
            if !dockerUpdatesPaused {
                await fetchDockerStats()
            }
        }
        try? await Task.sleep(for: .seconds(0.5))
        Task { await update() }
    }

    func connect() async throws {
        let _ = try await execute("echo hello")
        isConnected = true
        updatesPaused = false
        await SSHClientActor.shared.onDisconnect(of: credential) {[weak self] in
            Task{@MainActor in
                self?.isConnected = false
            }
        }
    }

    func disconnect() async throws {
        updatesPaused = true
        try await SSHClientActor.shared.disconnect(credential)
    }

    func fetchServerStats() async {
        await fetchMetric(command: "sar -u 1 2 | grep 'Average' | awk '{print (100 - $8) / 100}'", setter: { self.cpuUsage = $0 })
        await fetchMetric(command: "free | grep Mem | awk '{print $3/$2}'", setter: { self.memoryUsage = $0 })
        await fetchMetric(command: "df / | grep / | awk '{ print $5 / 100 }'", setter: { self.diskUsage = $0 })
        await fetchMetric(command: "sar -n DEV 1 2 | grep Average | grep eth0 | awk '{print $5 * 1024}'", setter: { self.networkUpstream = $0 })
        await fetchMetric(command: "sar -n DEV 1 2 | grep Average | grep eth0 | awk '{print $6 * 1024}'", setter: { self.networkDownstream = $0 })
        await fetchMetric(command: "free | grep Swap | awk '{print $3/$2}'", setter: { self.swapUsage = $0 })
        await fetchMetric(command: "sar -u 1 2 | grep 'Average' | awk '{print $5 / 100}'", setter: { self.ioWait = $0 })
        await fetchMetric(command: "sar -u 1 2 | grep 'Average' | awk '{print $6 / 100}'", setter: { self.stealTime = $0 })
        await fetchMetric(command: "uptime | awk '{print $(NF-2) / 100}'", setter: { self.systemLoad = $0 })
        if uptime == nil {
            let uptimeCommand = "date +%s -d \"$(uptime -s)\""
            let uptimeOutput = try? await execute(uptimeCommand)
            if let uptimeOutput,
               let timestamp = Double(uptimeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) {
                uptime = Date(timeIntervalSince1970: timestamp)
            }
        }
        lastUpdate = Date()
    }

    func fetchDockerStats() async {
        do {
            let output = try await execute("""
    docker stats --no-stream --format "{{.ID}} {{.Name}} {{.CPUPerc}} {{.MemUsage}}" | while read id name cpu mem; do
        status=$(docker ps --filter "id=$id" --format "{{.Status}}")
        
        # Fetch total memory for the container using docker inspect
        totalMem=$(docker inspect --format '{{.HostConfig.Memory}}' $id)

        # Check if totalMem is empty or zero, fallback to a default value
        if [ -z "$totalMem" ] || [ "$totalMem" -eq 0 ]; then
            totalMem="N/A"
        fi
        
        # Output the stats with both used memory and total memory
        echo "$id $name $cpu $mem $status"
    done
""")
            let stopped = try await execute("""
    docker ps -a --filter "status=exited" --format "{{.ID}} {{.Names}} {{.Status}}" | awk '{id=$1; name=$2; status=$3; cpu="0"; mem="0 / 0"; totalMem="N/A"; print id, name, cpu, mem, status}'
""")
            let newContainers = try parseDockerStats(from: "\(output)\n\(stopped)")

            for newContainer in newContainers {
                if let existingIndex = containers.firstIndex(where: { $0.id == newContainer.id }) {
                    let existingContainer = containers[existingIndex]
                    existingContainer.name = newContainer.name
                    existingContainer.cpuUsage = newContainer.cpuUsage
                    existingContainer.memoryUsage = newContainer.memoryUsage
                } else {
                    containers.append(
                        Container(
                            id: newContainer.id,
                            name: newContainer.name,
                            status: newContainer.status,
                            cpuUsage: newContainer.cpuUsage,
                            memoryUsage: newContainer.memoryUsage,
                            server: self
                        )
                    )
                }
            }

            containers.removeAll { container in
                !newContainers.contains(where: { $0.id == container.id })
            }

            for container in containers.filter({ $0.fetchDetailedUpdates }) {
                try await container.fetchDetails()
            }
        } catch {
            errors.insert(error as? ServerError ?? .otherError(error as NSError))
        }
    }

    private func fetchMetric(command: String, setter: @escaping (Double?) -> Void) async {
        do {
            let output = try await execute(command)
            setter(try parseSingleValue(from: output, command: command))
        } catch {
            errors.insert(error as? ServerError ?? .otherError(error as NSError))
        }
    }

    private func parseSingleValue(from output: String, command: String = "") throws(ServerError) -> Double {
        let lines = output.split(whereSeparator: \.isNewline)
        for line in lines {
            let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            if let value = Double(cleanedLine) {
                return value
            }
        }
        throw ServerError.invalidStatsOutput("\(command) failed: \(output)")
    }

    private func parseDockerStats(from output: String) throws(ServerError) -> [(id: String, name: String, status: String, cpuUsage: Double, memoryUsage: Double)] {
        do {
            let lines = output.split(whereSeparator: \.isNewline)
            return try lines.map { line in
                var parts = line.split(separator: " ", omittingEmptySubsequences: true)

                // Ensure there are enough parts to parse
                guard parts.count >= 6 else {
                    throw ServerError.invalidStatsOutput("Malformed or incomplete container info: \(line)")
                }

                let id = String(parts[0])
                let name = String(parts[1])
                let cpuUsageString = parts[2].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
                guard let cpuUsage = Double(cpuUsageString) else {
                    throw ServerError.invalidStatsOutput("Invalid CPU usage in line: \(line)")
                }

                // Memory usage parsing
                let memoryUsage = String(parts[3])

                let totalMemString = String(parts[5])


                let usedMemoryBytes = try parseMemoryUsage(memoryUsage)
                let totalMemoryBytes = try parseMemoryUsage(totalMemString)

                let memoryUsagePercentage = totalMemoryBytes.isZero ? 0 : (usedMemoryBytes / totalMemoryBytes)

                print(parts)
                parts.removeFirst(6)

                let status = String(parts.joined(separator: " "))

                return (id: id, name: name, status: status, cpuUsage: cpuUsage / 100, memoryUsage: memoryUsagePercentage)
            }
        } catch {
            throw error as! ServerError
        }
    }


    private func parseUsage(from usage: Substring) throws(ServerError) -> Double {
        if let value = Double(usage.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")) {
            return value
        }
        throw ServerError.invalidStatsOutput(String(usage))
    }


    private func parseMemoryUsage(_ memoryString: String) throws(ServerError) -> Double {
        let units = ["MiB": 1_048_576.0, "KiB": 1_024.0, "GiB": 1_073_741_824.0, "B": 1.0]

        // Loop over the units to check which one is present
        if memoryString == "0" || (memoryString.localizedCaseInsensitiveContains("N/A")) {
            return 0
        }
        for (unit, multiplier) in units {
            if memoryString.contains(unit) {
                let numericValue = memoryString.replacingOccurrences(of: unit, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(numericValue) {
                    return value * multiplier
                }
            }
        }
        // Handle the case where no valid unit is found
        throw .invalidStatsOutput("Couldn't parse memory usage from: \(memoryString)")
    }

    func execute(_ command: String) async throws -> String {

        let string: String
        do {
            string = try await SSHClientActor.shared.execute(command, on: credential)
        } catch {
            throw error
        }
        return string
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(lastUpdate)
        hasher.combine(isConnected)
    }

    static func == (lhs: Server, rhs: Server) -> Bool {
        lhs.id == rhs.id && lhs.lastUpdate == rhs.lastUpdate && lhs.isConnected == rhs.isConnected
    }
}
