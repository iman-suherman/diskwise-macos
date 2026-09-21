package net.suherman.diskwise.android.data

class DuplicateEngine {
    fun findExactDuplicates(assets: List<MediaAsset>): List<DuplicateGroup> {
        return assets
            .groupBy { it.exactFingerprint }
            .filter { it.value.size > 1 }
            .map { (fingerprint, members) ->
                DuplicateGroup(
                    id = "exact-$fingerprint",
                    fingerprint = fingerprint,
                    assets = members.sortedByDescending { it.byteSize }
                )
            }
            .sortedByDescending { it.reclaimableSize }
    }
}
