extension Array where Element: Equatable {
    func containsSubsequence(_ subsequence: [Element]) -> Bool {
        indices.contains { index in
            let end = index + subsequence.count
            return end <= count && Array(self[index..<end]) == subsequence
        }
    }
}
