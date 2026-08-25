//
//  ArtworkPrefetcher.swift
//  Gameball
//

import UIKit

/// Loads campaign artwork ahead of time and reports whether a campaign is drawable.
///
/// The whole set is warmed rather than one campaign at a time: an event trigger fires with
/// no warning and no time to fetch, so anything not already in memory would either delay the
/// message or draw a broken frame.
///
/// Readiness is defined as "every URL this campaign needs has a decoded image". A failed load,
/// a load that never happened, and bytes that are not an image all read the same way — not
/// ready — because the only sensible response to all three is to skip the campaign.
///
/// Nothing records *which* URLs failed, deliberately. There used to be a `failed` set, written on
/// every failure and read by nothing: the only thing such a record could be used for is skipping a
/// URL that failed before, and that is the opposite of what this wants — a failure is more often
/// the network than the asset, so the next warm should try again. `load` consults the image cache
/// alone, which gives that behaviour for free and has no second source of truth to keep in step.
final class ArtworkPrefetcher {
    private let session: URLSession
    private let timeout: TimeInterval

    private let queue = DispatchQueue(label: "co.gameball.inappmessaging.artwork")
    private let cache = NSCache<NSURL, UIImage>()

    init(session: URLSession = .shared, timeout: TimeInterval = 5) {
        self.session = session
        self.timeout = timeout
    }

    /// Warms every campaign's artwork concurrently, then calls back exactly once.
    ///
    /// The callback is bounded without blocking anything: the group finishing races a deadline of
    /// its own, layered over the per-request timeout, so a single hung request cannot stall the
    /// session forever.
    func warm(campaigns: [InAppMessageCampaign], completion: @escaping () -> Void) {
        var urls: [URL] = []
        var seen: Set<URL> = []
        for campaign in campaigns {
            for url in ArtworkPrefetcher.urls(for: campaign) where !seen.contains(url) {
                seen.insert(url)
                urls.append(url)
            }
        }

        guard !urls.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        for url in urls {
            group.enter()
            load(url) { group.leave() }
        }

        // The group finishing and the deadline expiring race each other, and whichever arrives
        // first delivers the callback. Both land on `queue`, which is serial, so the guard below
        // needs no lock.
        //
        // Deliberately *not* `group.wait(timeout:)` on a global queue: that blocks a pool thread
        // for the whole grace period, and blocking pool threads is what causes the thread
        // starvation that then delays the very block doing the waiting — a bounded wait measured
        // at 6.5s against a 1.5s deadline under load. Nothing here blocks.
        var hasDelivered = false
        let deliver: (Bool) -> Void = { [weak self] timedOut in
            guard let self = self, !hasDelivered else { return }
            hasDelivered = true
            if timedOut {
                iamLog("artwork warm-up hit its \(Int(self.timeout))s bound; campaigns whose "
                     + "artwork is still missing will be skipped")
            }
            // Handed off rather than run on `queue`: the caller's completion leads back into
            // `isReady`, which takes `queue.sync`, and re-entering a serial queue deadlocks.
            DispatchQueue.global(qos: .userInitiated).async { completion() }
        }

        group.notify(queue: queue) { deliver(false) }
        // A grace period over the per-request timeout, so a protocol or proxy that ignores the
        // request timeout still cannot pin the callback.
        queue.asyncAfter(deadline: .now() + timeout + 1) { deliver(true) }
    }

    func isReady(_ campaign: InAppMessageCampaign) -> Bool {
        let urls = ArtworkPrefetcher.urls(for: campaign)
        // Nothing to load is not the same as nothing loaded: a text-only campaign is always
        // drawable and must never be held back.
        guard !urls.isEmpty else { return true }
        for url in urls where image(for: url) == nil { return false }
        return true
    }

    func image(for url: URL) -> UIImage? {
        return queue.sync { cache.object(forKey: url as NSURL) }
    }

    /// Clears readiness so the next sync re-evaluates.
    func reset() {
        queue.sync { cache.removeAllObjects() }
    }

    // MARK: - Internals

    private static func urls(for campaign: InAppMessageCampaign) -> [URL] {
        return [campaign.message.imageURL, campaign.message.iconURL].compactMap { $0 }
    }

    private func load(_ url: URL, completion: @escaping () -> Void) {
        let alreadyHave = queue.sync { cache.object(forKey: url as NSURL) != nil }
        if alreadyHave {
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else {
                completion()
                return
            }

            if let error = error {
                iamLog("artwork failed to load from \(url): \(error.localizedDescription)")
                completion()
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                iamLog("artwork at \(url) is not a decodable image")
                completion()
                return
            }

            self.queue.sync { self.cache.setObject(image, forKey: url as NSURL) }
            completion()
        }.resume()
    }
}
