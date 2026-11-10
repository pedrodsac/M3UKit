import Foundation
import Testing
@testable import M3UKit

private struct EpisodeTitle: CustomTestStringConvertible, Sendable {
    var title: String
    var name: String
    var season: Int
    var episode: Int
    var episodeTitle: String?
    var year: Int?
    var airDate: String?

    var testDescription: String { title }
}

private let episodes: [EpisodeTitle] = [
    EpisodeTitle(title: "Severance S02E03", name: "Severance", season: 2, episode: 3),
    EpisodeTitle(title: "Severance S02 E03", name: "Severance", season: 2, episode: 3),
    EpisodeTitle(title: "Show S01.E01", name: "Show", season: 1, episode: 1),
    EpisodeTitle(title: "Show s01e01", name: "Show", season: 1, episode: 1),
    EpisodeTitle(title: "Show - S01E01 - Pilot", name: "Show", season: 1, episode: 1, episodeTitle: "Pilot"),
    EpisodeTitle(title: "Show (2019) S01 E01", name: "Show", season: 1, episode: 1, year: 2019),
    EpisodeTitle(title: "Show [2019] S03E10: The End", name: "Show", season: 3, episode: 10, episodeTitle: "The End", year: 2019),
    EpisodeTitle(title: "The.Show.Name.S01E05.Episode.Name", name: "The Show Name", season: 1, episode: 5, episodeTitle: "Episode.Name"),
    EpisodeTitle(title: "The_Show_S01E05", name: "The Show", season: 1, episode: 5),
    EpisodeTitle(title: "Spider-Man S01E01", name: "Spider-Man", season: 1, episode: 1),
    EpisodeTitle(title: "Show 1x02", name: "Show", season: 1, episode: 2),
    EpisodeTitle(title: "Show Season 2 Episode 5", name: "Show", season: 2, episode: 5),
    EpisodeTitle(title: "Show Season 2 Ep 5 - Name", name: "Show", season: 2, episode: 5, episodeTitle: "Name"),
    EpisodeTitle(title: "IEGCQT 05 05 2025 S2025E05", name: "IEGCQT", season: 2025, episode: 5, airDate: "05 05 2025"),
    EpisodeTitle(title: "Daily Show S2025E05 - 05-05-2025", name: "Daily Show", season: 2025, episode: 5, airDate: "05-05-2025"),
    EpisodeTitle(title: "Show S01E01E02", name: "Show", season: 1, episode: 1, episodeTitle: "E02"),
]

@Test(arguments: episodes)
private func parsesEpisodeTitle(_ expected: EpisodeTitle) throws {
    let info = try #require(SeriesInfo(title: expected.title))
    #expect(info.name == expected.name)
    #expect(info.season == expected.season)
    #expect(info.episode == expected.episode)
    #expect(info.episodeTitle == expected.episodeTitle)
    #expect(info.year == expected.year)
    #expect(info.airDate == expected.airDate)
}

@Test(arguments: [
    "BBC One HD",
    "Dune: Part Two (2024)",
    "Eurosport 2",
    "Movie 1920x1080",
    "Channel 4",
    "S01",
    "",
])
private func ignoresTitlesWithoutAnEpisodeMarker(_ title: String) {
    #expect(SeriesInfo(title: title) == nil)
}

@Test func aTitleThatIsOnlyAMarkerStillNamesTheShow() throws {
    let info = try #require(SeriesInfo(title: "S01E01 Pilot"))
    #expect(info.name == "Pilot")
    #expect(info.season == 1)
    #expect(info.episode == 1)
    #expect(info.episodeTitle == nil)
}

@Test func seriesInfoDecodesJSONWrittenBeforeTheNewFields() throws {
    let json = #"{"name":"Show","season":1,"episode":2}"#
    let info = try JSONDecoder().decode(SeriesInfo.self, from: Data(json.utf8))
    #expect(info == SeriesInfo(name: "Show", season: 1, episode: 2))
}
