/// Disjoint-set forest used to turn pairwise "these match" decisions into groups.
struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }
        var node = element
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let left = find(lhs), right = find(rhs)
        guard left != right else { return }
        if rank[left] < rank[right] {
            parent[left] = right
        } else if rank[left] > rank[right] {
            parent[right] = left
        } else {
            parent[right] = left
            rank[left] += 1
        }
    }

    /// Groups with more than one member, each sorted by index; groups sorted by first index.
    mutating func groups() -> [[Int]] {
        var byRoot: [Int: [Int]] = [:]
        for index in parent.indices {
            byRoot[find(index), default: []].append(index)
        }
        return byRoot.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }
}
