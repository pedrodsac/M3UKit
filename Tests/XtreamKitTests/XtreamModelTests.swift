import Foundation
import Testing
@testable import XtreamKit

private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(Value.self, from: Data(json.utf8))
}

// MARK: - Account

@Test func readsAnAccountWhoseNumbersAreStrings() throws {
    let json = """
    {"user_info":{"username":"johndoe","password":"s3cret","message":"Welcome","auth":1,"status":"Active",
    "exp_date":"1798761600","is_trial":"0","active_cons":"1","created_at":"1700000000","max_connections":"3",
    "allowed_output_formats":["m3u8","ts"]},
    "server_info":{"url":"panel.example","port":"8080","https_port":"443","server_protocol":"http","rtmp_port":"1935",
    "timezone":"Europe/London","timestamp_now":1767225600,"time_now":"2026-01-01 00:00:00","process":true}}
    """

    let info = try decode(XtreamAccountResponse.self, json).info

    #expect(info.username == "johndoe")
    #expect(info.message == "Welcome")
    #expect(info.isAuthenticated)
    #expect(info.status == .active)
    #expect(info.expiresAt == 1_798_761_600)
    #expect(info.isTrial == false)
    #expect(info.activeConnections == 1)
    #expect(info.maxConnections == 3)
    #expect(info.createdAt == 1_700_000_000)
    #expect(info.allowedOutputFormats == ["m3u8", "ts"])
    #expect(info.serverURL == "panel.example")
    #expect(info.serverPort == 8080)
    #expect(info.httpsPort == 443)
    #expect(info.timeZoneID == "Europe/London")
    #expect(info.timeZone?.identifier == "Europe/London")
    #expect(info.serverTimestamp == 1_767_225_600)
    #expect(info.isXUI == false)
    #expect(info.preferredLiveExtension == "m3u8")
    #expect(info.isExpired(at: Date(timeIntervalSince1970: 1_700_000_000)) == false)
    #expect(info.isExpired(at: Date(timeIntervalSince1970: 1_800_000_000)))
}

@Test func readsAnXUIAccountWithNoExpiryAndBooleans() throws {
    let json = """
    {"user_info":{"username":"u","auth":true,"status":"Active","exp_date":null,"is_trial":true,"max_connections":2},
    "server_info":{"xui":true,"version":"v26.10","revision":null}}
    """

    let info = try decode(XtreamAccountResponse.self, json).info

    #expect(info.isAuthenticated)
    #expect(info.expiresAt == nil)
    #expect(info.isTrial)
    #expect(info.maxConnections == 2)
    #expect(info.isXUI)
    #expect(info.version == "v26.10")
    #expect(info.revision == nil)
    #expect(info.isExpired() == false)
}

@Test func anAccountWithoutExpiryDateZeroNeverExpires() throws {
    let info = try decode(XtreamAccountResponse.self, #"{"user_info":{"auth":1,"status":"Active","exp_date":"0"}}"#).info
    #expect(info.expiresAt == nil)
}

@Test func choosesTranportStreamWhenHLSIsNotAllowed() throws {
    let json = #"{"user_info":{"auth":1,"status":"Active","allowed_output_formats":["ts","rtmp"]}}"#
    let info = try decode(XtreamAccountResponse.self, json).info
    #expect(info.allowsHLS == false)
    #expect(info.preferredLiveExtension == "ts")
}

@Test(arguments: [
    (#"{"user_info":{"auth":0,"status":"Inactive"}}"#, XtreamError.accountRejected),
    (#"{"user_info":{"auth":1,"status":"Banned"}}"#, XtreamError.accountBanned),
    (#"{"user_info":{"auth":1,"status":"Disabled"}}"#, XtreamError.accountDisabled),
    (#"{"user_info":{"auth":1,"status":"Expired","exp_date":"1700000000"}}"#, XtreamError.accountExpired(Date(timeIntervalSince1970: 1_700_000_000))),
    (#"{"user_info":{"auth":1,"status":"Active","exp_date":"1700000000"}}"#, XtreamError.accountExpired(Date(timeIntervalSince1970: 1_700_000_000))),
])
private func explainsWhyALineCannotBeUsed(_ json: String, _ expected: XtreamError) throws {
    let info = try decode(XtreamAccountResponse.self, json).info
    #expect(throws: expected) { try info.requireUsable(at: Date(timeIntervalSince1970: 1_800_000_000)) }
}

@Test func anActiveLineIsUsable() throws {
    let info = try decode(XtreamAccountResponse.self, #"{"user_info":{"auth":1,"status":"Active","exp_date":"1900000000"}}"#).info
    try info.requireUsable(at: Date(timeIntervalSince1970: 1_800_000_000))
}

@Test func accountInfoRoundTripsThroughCodable() throws {
    let json = #"{"user_info":{"username":"u","auth":1,"status":"Active","max_connections":"3"},"server_info":{"timezone":"UTC"}}"#
    let info = try decode(XtreamAccountResponse.self, json).info
    let stored = try JSONDecoder().decode(XtreamAccountInfo.self, from: JSONEncoder().encode(info))
    #expect(stored == info)
}

// MARK: - Catalog

@Test func readsCategoriesWhoseIDsAreNumbersOrStrings() throws {
    let list = try XtreamList<XtreamCategory>.decode(Data(#"""
    [{"category_id":"12","category_name":"UK | Entertainment","parent_id":0},
     {"category_id":13,"category_name":"UK | News","parent_id":"12"},
     {"category_name":"No ID"}]
    """#.utf8))

    #expect(list.items.map(\.categoryID) == ["12", "13"])
    #expect(list.items.map(\.parentID) == [0, 12])
    #expect(list.droppedCount == 1)
}

@Test func readsALiveStreamWithEveryFieldAString() throws {
    let stream = try decode(XtreamLiveStream.self, """
    {"num":"7","name":"UK: BBC One HD","stream_type":"live","stream_id":"10234","stream_icon":"http://l/bbc1.png",
    "epg_channel_id":"bbcone.uk","added":"1700000000","is_adult":"0","category_id":"12","category_ids":[12,45],
    "custom_sid":"","tv_archive":"1","direct_source":"","tv_archive_duration":"7","thumbnail":"http://t/1.jpg"}
    """)

    #expect(stream.num == 7)
    #expect(stream.name == "UK: BBC One HD")
    #expect(stream.streamID == 10234)
    #expect(stream.iconURL == "http://l/bbc1.png")
    #expect(stream.epgChannelID == "bbcone.uk")
    #expect(stream.added == 1_700_000_000)
    #expect(stream.isAdult == false)
    #expect(stream.categoryID == "12")
    #expect(stream.categoryIDs == [12, 45])
    #expect(stream.customSID == nil)
    #expect(stream.hasArchive)
    #expect(stream.archiveDays == 7)
    #expect(stream.directSource == nil)
    #expect(stream.thumbnailURL == "http://t/1.jpg")
    #expect(stream.isRadio == false)
}

@Test func tellsLiveRadioAndCreatedLiveApart() throws {
    let radio = try decode(XtreamLiveStream.self, #"{"name":"Nova","stream_type":"radio_streams","stream_id":1}"#)
    let loop = try decode(XtreamLiveStream.self, #"{"name":"24/7 Friends","stream_type":"created_live","stream_id":2}"#)
    let missing = try decode(XtreamLiveStream.self, #"{"name":"Plain","stream_id":3,"epg_channel_id":null,"is_adult":1}"#)

    #expect(radio.isRadio)
    #expect(loop.isCreatedLive)
    #expect(missing.streamType == nil)
    #expect(missing.epgChannelID == nil)
    #expect(missing.isAdult)
}

@Test func skipsStreamsWithoutAnIDAndCountsThem() throws {
    let list = try XtreamList<XtreamLiveStream>.decode(Data(#"""
    [{"name":"A","stream_id":1},{"name":"No ID"},"junk",{"name":"B","stream_id":"2"}]
    """#.utf8))

    #expect(list.items.map(\.streamID) == [1, 2])
    #expect(list.droppedCount == 2)
}

@Test func readsAListThePanelSentAsAnObjectOfItems() throws {
    // PHP encodes an array whose keys aren't a plain sequence as an object.
    let list = try XtreamList<XtreamLiveStream>.decode(Data(#"""
    {"2":{"name":"C","stream_id":3},"0":{"name":"A","stream_id":1},"10":{"name":"D","stream_id":4},"1":{"name":"B","stream_id":2}}
    """#.utf8))

    #expect(list.items.map(\.streamID) == [1, 2, 3, 4])
}

@Test func readsAMovieListItemWithXUIExtras() throws {
    let movie = try decode(XtreamVODStream.self, """
    {"num":3,"name":"Dune: Part Two (2024)","title":"Dune: Part Two","year":"2024","stream_id":55120,
    "stream_icon":"http://p/dune.jpg","rating":"8.4","rating_5based":4.2,"added":"1700000000","is_adult":0,
    "category_id":"30","category_ids":[30],"container_extension":"MKV","custom_sid":null,"direct_source":"",
    "plot":"Paul Atreides","cast":"Timothee Chalamet","director":"Denis Villeneuve","genre":"Sci-Fi",
    "release_date":"2024-03-01","youtube_trailer":"Way9Dexny3w","episode_run_time":166,"tmdb_id":"693134"}
    """)

    #expect(movie.name == "Dune: Part Two (2024)")
    #expect(movie.title == "Dune: Part Two")
    #expect(movie.year == 2024)
    #expect(movie.rating == 8.4)
    #expect(movie.rating10 == 8.4)
    #expect(movie.containerExtension == "mkv")
    #expect(movie.plot == "Paul Atreides")
    #expect(movie.episodeRunTime == 166)
    #expect(movie.tmdbID == "693134")
    #expect(movie.youtubeTrailer == "Way9Dexny3w")
}

@Test func fallsBackToTheFiveStarRatingAndTreatsZeroAsNone() throws {
    let fiveStar = try decode(XtreamVODStream.self, #"{"name":"A","stream_id":1,"rating":"","rating_5based":3.5}"#)
    let none = try decode(XtreamVODStream.self, #"{"name":"B","stream_id":2,"rating":"0","rating_5based":0}"#)

    #expect(fiveStar.rating10 == 7)
    #expect(none.rating10 == nil)
}

@Test(arguments: [("2021", 2021), ("2021-03-04", 2021), ("(2019)", 2019), ("", nil), ("12345", nil), ("n/a", nil)] as [(String, Int?)])
private func readsAYearFromWhateverTheFieldHolds(_ value: String, _ expected: Int?) throws {
    let stream = try decode(XtreamVODStream.self, #"{"name":"A","stream_id":1,"year":"\#(value)"}"#)
    #expect(stream.year == expected)
}

@Test func readsAShowWhoseRatingIsAStringAndBackdropIsAString() throws {
    let series = try decode(XtreamSeries.self, """
    {"num":1,"name":"Severance (2022)","title":"Severance","year":"2022","series_id":"901","cover":"http://c/s.jpg",
    "plot":"Work","cast":"A, B","director":"D","genre":"Drama","releaseDate":"2022-02-18","last_modified":"1700000000",
    "rating":"8.7","rating_5based":"4.35","backdrop_path":"http://b/s.jpg","youtube_trailer":"","episode_run_time":"50",
    "category_id":"7","category_ids":[7]}
    """)

    #expect(series.seriesID == 901)
    #expect(series.title == "Severance")
    #expect(series.releaseDate == "2022-02-18")
    #expect(series.lastModified == 1_700_000_000)
    #expect(series.rating == 8.7)
    #expect(series.backdropURLs == ["http://b/s.jpg"])
    #expect(series.youtubeTrailer == nil)
    #expect(series.episodeRunTime == 50)
}

@Test(arguments: [
    (#"["http://b/1.jpg","http://b/2.jpg"]"#, ["http://b/1.jpg", "http://b/2.jpg"]),
    (#""http://b/1.jpg""#, ["http://b/1.jpg"]),
    (#""""#, []),
    ("[]", []),
    ("null", []),
] as [(String, [String])])
private func readsBackdropsInEveryShapeThePanelUses(_ value: String, _ expected: [String]) throws {
    let series = try decode(XtreamSeries.self, #"{"name":"A","series_id":1,"backdrop_path":\#(value)}"#)
    #expect(series.backdropURLs == expected)
}

// MARK: - Details

@Test func readsAMovieInfoWithFfprobeStreams() throws {
    let json = """
    {"info":{"kinopoisk_url":"https://kp/1","tmdb_id":"693134","name":"Dune: Part Two","o_name":"Dune: Part Two",
    "cover_big":"http://p/big.jpg","movie_image":"http://p/small.jpg","release_date":"2024-03-01",
    "episode_run_time":"166","youtube_trailer":"Way9Dexny3w","director":"Denis Villeneuve","actors":"Timothee Chalamet",
    "description":"Paul Atreides","age":"12+","mpaa_rating":"PG-13","rating_count_kinopoisk":"12345","country":"US",
    "genre":"Sci-Fi, Adventure","backdrop_path":["http://b/1.jpg"],"duration_secs":9960,"duration":"02:46:00",
    "video":{"index":0,"codec_name":"hevc","profile":"Main 10","width":3840,"height":2160,"display_aspect_ratio":"16:9",
    "r_frame_rate":"24000/1001","pix_fmt":"yuv420p10le","color_transfer":"smpte2084","color_primaries":"bt2020",
    "codec_tag_string":"[0][0][0][0]","disposition":{"default":1}},
    "audio":{"codec_name":"eac3","channels":6,"channel_layout":"5.1(side)","sample_rate":"48000","bit_rate":"640000",
    "tags":{"language":"eng"}},
    "bitrate":18000,"rating":"8.4","subtitles":[{"tags":{"language":"eng"}},{"tags":{"language":"fra"}}]},
    "movie_data":{"stream_id":55120,"name":"Dune: Part Two (2024)","added":"1700000000","category_id":"30",
    "container_extension":"mkv","custom_sid":"","direct_source":""}}
    """

    let vod = try decode(XtreamVODInfo.self, json)
    let info = try #require(vod.info)

    #expect(info.tmdbID == "693134")
    #expect(info.originalName == "Dune: Part Two")
    #expect(info.cast == "Timothee Chalamet")
    #expect(info.plot == "Paul Atreides")
    #expect(info.releaseDate == "2024-03-01")
    #expect(info.mpaaRating == "PG-13")
    #expect(info.ratingCountKinopoisk == 12345)
    #expect(info.backdropURLs == ["http://b/1.jpg"])
    #expect(info.runtimeMinutes == 166)
    #expect(info.bitrate == 18000)
    #expect(info.subtitles == ["eng", "fra"])

    let video = try #require(info.video)
    #expect(video.codecName == "hevc")
    #expect(video.resolutionLabel == "4K")
    #expect(video.isHDR)
    #expect(video.isDolbyVision == false)
    #expect(video.pixelFormat == "yuv420p10le")

    let audio = try #require(info.audio)
    #expect(audio.codecName == "eac3")
    #expect(audio.channels == 6)
    #expect(audio.language == "eng")

    #expect(vod.movieData?.streamID == 55120)
    #expect(vod.movieData?.containerExtension == "mkv")
    #expect(vod.isMissing == false)
}

@Test func aMissingMovieReadsAsMissing() throws {
    let vod = try decode(XtreamVODInfo.self, #"{"info":[]}"#)
    #expect(vod.isMissing)
}

@Test func aMovieInfoWithEmptyArraysForItsStreamsStillReads() throws {
    let vod = try decode(XtreamVODInfo.self, #"{"info":{"name":"A","video":[],"audio":[],"subtitles":[],"backdrop_path":""}}"#)
    let info = try #require(vod.info)
    #expect(info.video == nil)
    #expect(info.audio == nil)
    #expect(info.subtitles.isEmpty)
    #expect(info.backdropURLs.isEmpty)
}

@Test(arguments: [(3840, 2160, "4K"), (1920, 1080, "HD"), (1280, 720, "HD"), (720, 576, "SD"), (1920, 800, "HD")] as [(Int, Int, String)])
private func labelsAResolution(_ width: Int, _ height: Int, _ expected: String) throws {
    let stream = try decode(XtreamMediaStream.self, #"{"width":\#(width),"height":\#(height)}"#)
    #expect(stream.resolutionLabel == expected)
}

@Test func recognisesDolbyVisionAndHLG() throws {
    let vision = try decode(XtreamMediaStream.self, #"{"codec_tag_string":"dvh1","color_transfer":"smpte2084"}"#)
    let hlg = try decode(XtreamMediaStream.self, #"{"color_transfer":"arib-std-b67"}"#)
    #expect(vision.isDolbyVision)
    #expect(hlg.isHDR)
}

@Test func readsSeriesInfoWithEpisodesKeyedBySeason() throws {
    let json = """
    {"seasons":[],"info":{"name":"Demo Show (2020)","cover":"http://i/c.jpg","plot":"p","rating":"7.5",
    "backdrop_path":["http://i/b1.jpg"],"last_modified":"1700000000","category_id":"12","episode_run_time":"45"},
    "episodes":{"1":[{"id":"101","episode_num":"1","title":"Demo Show - S01E01 - Pilot","container_extension":"mkv",
    "info":{"tmdb_id":"900","releasedate":"2020-01-02","plot":"x","duration_secs":2700,"movie_image":"http://i/e1.jpg",
    "rating":7.1,"season":"1"},"season":1},
    {"id":102,"episode_num":2,"title":"Demo Show - S01E02","container_extension":"mp4","info":[],"season":1}],
    "0":[{"id":"100","episode_num":"1","title":"Special","container_extension":"mp4","season":0}]}}
    """

    let show = try decode(XtreamSeriesInfo.self, json)

    #expect(show.info?.name == "Demo Show (2020)")
    #expect(show.info?.seriesID == nil)
    #expect(show.episodes.map(\.id) == [100, 101, 102])
    #expect(show.episodes.map(\.season) == [0, 1, 1])
    #expect(show.seasons.map(\.seasonNumber) == [0, 1])

    let pilot = show.episodes[1]
    #expect(pilot.episodeNumber == 1)
    #expect(pilot.containerExtension == "mkv")
    #expect(pilot.info?.airDate == "2020-01-02")
    #expect(pilot.info?.durationSeconds == 2700)
    #expect(pilot.info?.imageURL == "http://i/e1.jpg")
    #expect(pilot.info?.rating == 7.1)
    #expect(pilot.info?.tmdbID == "900")
    #expect(show.episodes[2].info == nil)
}

@Test func theKeyOfASeasonWinsOverTheEpisodesOwnField() throws {
    let show = try decode(XtreamSeriesInfo.self, #"{"episodes":{"2":[{"id":1,"episode_num":1,"title":"A","season":5}]}}"#)
    #expect(show.episodes.first?.season == 2)
}

@Test func readsSeriesInfoWithEpisodesAsAnArrayOfArrays() throws {
    let show = try decode(XtreamSeriesInfo.self, #"""
    {"episodes":[[{"id":"1","episode_num":"1","title":"A"}],[{"id":"2","episode_num":"1","title":"B"}]]}
    """#)

    #expect(show.episodes.map(\.season) == [1, 2])
    #expect(show.seasons.map(\.seasonNumber) == [1, 2])
}

@Test func keepsTheSeasonsThePanelListsAndReadsTheirDetails() throws {
    let show = try decode(XtreamSeriesInfo.self, """
    {"seasons":[{"id":"55","name":"Season 1","season_number":"1","episode_count":"10","overview":"o",
    "air_date":"2020-01-02","cover":"http://i/s1.jpg","cover_big":"http://i/s1b.jpg","vote_average":"7.4"},
    {"name":"No number"}],"episodes":{}}
    """)

    #expect(show.seasons.count == 1)
    let season = try #require(show.seasons.first)
    #expect(season.seasonNumber == 1)
    #expect(season.episodeCount == 10)
    #expect(season.coverBigURL == "http://i/s1b.jpg")
    #expect(season.voteAverage == 7.4)
}

@Test func aMissingShowReadsWithNoInfoOrEpisodes() throws {
    let show = try decode(XtreamSeriesInfo.self, #"{"seasons":[],"info":[],"episodes":[]}"#)
    #expect(show.info == nil)
    #expect(show.episodes.isEmpty)
    #expect(show.seasons.isEmpty)
}

@Test func skipsAnEpisodeWithoutAnID() throws {
    let show = try decode(XtreamSeriesInfo.self, #"{"episodes":{"1":[{"title":"No ID"},{"id":9,"title":"Ok"}]}}"#)
    #expect(show.episodes.map(\.id) == [9])
}

// MARK: - Guide

private func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

@Test func readsAnEPGListingAndDecodesItsBase64Text() throws {
    let json = """
    {"id":"9001","epg_id":"5","title":"\(base64("Now Showing"))","lang":"en","start":"2023-11-14 22:13:20",
    "end":"2023-11-14 23:13:20","description":"\(base64("A description. Ünïcode ✓"))","channel_id":"bbcone.uk",
    "start_timestamp":"1700000000","stop_timestamp":"1700003600"}
    """

    let listing = try decode(XtreamEPGListing.self, json)

    #expect(listing.id == "9001")
    #expect(listing.channelID == "bbcone.uk")
    #expect(listing.title == "Now Showing")
    #expect(listing.summary == "A description. Ünïcode ✓")
    #expect(listing.language == "en")
    #expect(listing.start == 1_700_000_000)
    #expect(listing.end == 1_700_003_600)
    #expect(listing.startDate == Date(timeIntervalSince1970: 1_700_000_000))
}

@Test func readsTheSimpleDataTableFlags() throws {
    let listing = try decode(XtreamEPGListing.self, """
    {"id":"1","title":"\(base64("Past"))","start_timestamp":"1700000000","stop_timestamp":"1700003600",
    "end":"2023-11-14 23:13:20","now_playing":0,"has_archive":1}
    """)

    #expect(listing.isNowPlaying == false)
    #expect(listing.hasArchive == true)
    #expect(listing.end == 1_700_003_600)
}

@Test func readsTimesThatAreNumbersWhenThereAreNoTimestamps() throws {
    let listing = try decode(XtreamEPGListing.self, #"{"id":"1","title":"Plain","start":1700000000,"end":1700003600}"#)
    #expect(listing.start == 1_700_000_000)
    #expect(listing.end == 1_700_003_600)
}

@Test func leavesADateStringForTheCallerBecauseItsZoneIsThePanels() throws {
    let listing = try decode(XtreamEPGListing.self, #"{"id":"1","title":"Plain","start":"2023-11-14 22:13:20","end":"2023-11-14 23:13:20"}"#)
    #expect(listing.start == nil)
    #expect(listing.end == nil)
}

@Test(arguments: [
    ("Now Showing", true),
    ("News", false),
    ("Test", false),
    ("Doctor Who", false),
    ("Film", false),
] as [(String, Bool)])
private func onlyDecodesTextThatIsReallyBase64(_ text: String, _ isEncoded: Bool) {
    let written = isEncoded ? base64(text) : text
    #expect(XtreamValue.decodeBase64Text(written) == text)
}

@Test func decodesBase64WithoutPaddingAndURLSafeLetters() {
    let text = "Why? Because >>> ???"
    let unpadded = base64(text)
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(XtreamValue.decodeBase64Text(unpadded) == text)
}

@Test func readsAWrappedAndABareEPGResponse() throws {
    let wrapped = try decode(XtreamEPGResponse.self, #"{"epg_listings":[{"id":"1","title":"A"},"junk"]}"#)
    let bare = try decode(XtreamEPGResponse.self, #"[{"id":"1","title":"A"},{"id":"2","title":"B"}]"#)

    #expect(wrapped.listings.items.map(\.id) == ["1"])
    #expect(wrapped.listings.droppedCount == 1)
    #expect(bare.listings.items.map(\.id) == ["1", "2"])
}
