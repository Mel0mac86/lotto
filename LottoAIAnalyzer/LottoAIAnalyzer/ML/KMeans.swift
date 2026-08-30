import Foundation

/// Clustering k-means con inizializzazione deterministica (k-means++ con seme fisso).
enum KMeans {

    struct Result: Sendable {
        var centroids: [[Double]]
        var assignments: [Int]
        var inertia: Double
    }

    static func fit(points: [[Double]], clusters k: Int, seed: UInt64 = 1, iterations: Int = 60) -> Result {
        guard !points.isEmpty, k > 0 else { return Result(centroids: [], assignments: [], inertia: 0) }
        let k = min(k, points.count)
        var generator = SeededRandom(seed: seed)
        var centroids = initialCentroids(points: points, k: k, generator: &generator)
        var assignments = [Int](repeating: 0, count: points.count)

        for _ in 0..<iterations {
            var changed = false
            for (index, point) in points.enumerated() {
                var bestCluster = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for (cluster, centroid) in centroids.enumerated() {
                    let distance = squaredDistance(point, centroid)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestCluster = cluster
                    }
                }
                if assignments[index] != bestCluster {
                    assignments[index] = bestCluster
                    changed = true
                }
            }

            var sums = Array(repeating: [Double](repeating: 0, count: points[0].count), count: k)
            var counts = [Int](repeating: 0, count: k)
            for (index, point) in points.enumerated() {
                let cluster = assignments[index]
                counts[cluster] += 1
                for dimension in 0..<point.count { sums[cluster][dimension] += point[dimension] }
            }
            for cluster in 0..<k where counts[cluster] > 0 {
                centroids[cluster] = sums[cluster].map { $0 / Double(counts[cluster]) }
            }
            if !changed { break }
        }

        let inertia = points.enumerated().reduce(0.0) { partial, item in
            partial + squaredDistance(item.element, centroids[assignments[item.offset]])
        }
        return Result(centroids: centroids, assignments: assignments, inertia: inertia)
    }

    private static func initialCentroids(points: [[Double]], k: Int, generator: inout SeededRandom) -> [[Double]] {
        var centroids: [[Double]] = []
        let firstIndex = Int(generator.next() % UInt64(points.count))
        centroids.append(points[firstIndex])

        while centroids.count < k {
            let distances = points.map { point in
                centroids.map { squaredDistance(point, $0) }.min() ?? 0
            }
            let total = distances.reduce(0, +)
            guard total > 0 else {
                centroids.append(points[Int(generator.next() % UInt64(points.count))])
                continue
            }
            var threshold = generator.nextUnit() * total
            var chosen = points.count - 1
            for (index, distance) in distances.enumerated() {
                threshold -= distance
                if threshold <= 0 { chosen = index; break }
            }
            centroids.append(points[chosen])
        }
        return centroids
    }

    static func squaredDistance(_ a: [Double], _ b: [Double]) -> Double {
        var total = 0.0
        for index in 0..<Swift.min(a.count, b.count) {
            let difference = a[index] - b[index]
            total += difference * difference
        }
        return total
    }
}
