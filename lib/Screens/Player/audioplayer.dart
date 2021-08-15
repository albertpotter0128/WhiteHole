import 'dart:async';
import 'package:blackhole/CustomWidgets/add_playlist.dart';
import 'package:blackhole/CustomWidgets/downloadButton.dart';
import 'package:blackhole/CustomWidgets/equalizer.dart';
import 'package:blackhole/CustomWidgets/gradientContainers.dart';
import 'package:blackhole/CustomWidgets/like_button.dart';
import 'package:blackhole/CustomWidgets/textinput_dialog.dart';
import 'package:blackhole/Helpers/lyrics.dart';
import 'package:blackhole/Helpers/mediaitem_converter.dart';
import 'package:blackhole/Services/audioService.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:miniplayer/miniplayer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:blackhole/CustomWidgets/emptyScreen.dart';
import 'package:blackhole/CustomWidgets/seekBar.dart';
import 'package:url_launcher/url_launcher.dart';

class PlayScreen extends StatefulWidget {
  final Map data;
  final controller;
  final bool fromMiniplayer;
  PlayScreen(
      {Key key,
      @required this.data,
      @required this.fromMiniplayer,
      this.controller})
      : super(key: key);
  @override
  _PlayScreenState createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  bool fromMiniplayer = false;
  String preferredQuality =
      Hive.box('settings').get('streamingQuality') ?? '96 kbps';
  String preferredDownloadQuality =
      Hive.box('settings').get('downloadQuality') ?? '320 kbps';
  String repeatMode = Hive.box('settings').get('repeatMode') ?? 'None';
  bool enforceRepeat =
      Hive.box('settings').get('enforceRepeat', defaultValue: false);
  bool stopServiceOnPause =
      Hive.box('settings').get('stopServiceOnPause') ?? true;
  bool shuffle = Hive.box('settings').get('shuffle') ?? false;
  List<MediaItem> globalQueue = [];
  int globalIndex = 0;
  bool same = false;
  List response = [];
  bool fetched = false;
  bool offline = false;
  bool fromYT = false;
  String defaultCover = '';
  MediaItem playItem;
  static const double minExtent = 0.1;
  static const double maxExtent = 1;
  bool isExpanded = false;
  double initialExtent = minExtent;
  int oldIndex;

  // final _controller = PageController();
  // sleepTimer(0) cancels the timer
  void sleepTimer(int time) {
    AudioService.customAction('sleepTimer', time);
  }

  void sleepCounter(int count) {
    AudioService.customAction('sleepCounter', count);
  }

  Duration _time;

  void main() async {
    await Hive.openBox('Favorite Songs');
  }

  @override
  void initState() {
    super.initState();
    main();
  }

  Future<MediaItem> setTags(Map response, Directory tempDir) async {
    String playTitle = response['title'];
    playTitle == ''
        ? playTitle = response['id']
            .split('/')
            .last
            .replaceAll('.m4a', '')
            .replaceAll('.mp3', '')
        : playTitle = response['title'];
    String playArtist = response['artist'];
    playArtist == ''
        ? playArtist = response['id']
            .split('/')
            .last
            .replaceAll('.m4a', '')
            .replaceAll('.mp3', '')
        : playArtist = response['artist'];

    String playAlbum = response['album'];
    final playDuration = response['duration'] ?? 180;
    String filePath;
    if (response['image'] != null) {
      try {
        File file = File(
            '${tempDir.path}/${playTitle.toString().replaceAll('/', '')}-${playArtist.toString().replaceAll('/', '')}.jpg');
        filePath = file.path;
        if (!await file.exists()) {
          await file.create();
          file.writeAsBytesSync(response['image']);
        }
      } catch (e) {
        filePath = null;
      }
    } else {
      filePath = await getImageFileFromAssets();
    }

    MediaItem tempDict = MediaItem(
        id: response['id'],
        album: playAlbum,
        duration: Duration(seconds: playDuration),
        title: playTitle != null ? playTitle.split("(")[0] : 'Unknown',
        artist: playArtist ?? 'Unknown',
        artUri: Uri.file(filePath),
        extras: {'url': response['id']});
    return tempDict;
  }

  Future<String> getImageFileFromAssets() async {
    if (defaultCover != '') return defaultCover;
    final file = File('${(await getTemporaryDirectory()).path}/cover.jpg');
    defaultCover = file.path;
    if (await file.exists()) return file.path;
    final byteData = await rootBundle.load('assets/cover.jpg');
    await file.writeAsBytes(byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file.path;
  }

  void setOffValues(List response) {
    getTemporaryDirectory().then((tempDir) async {
      final File file =
          File('${(await getTemporaryDirectory()).path}/cover.jpg');
      if (!await file.exists()) {
        final byteData = await rootBundle.load('assets/cover.jpg');
        await file.writeAsBytes(byteData.buffer
            .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      }
      for (int i = 0; i < response.length; i++) {
        globalQueue.add(await setTags(response[i], tempDir));
      }
      setState(() {});
    });
  }

  void setValues(List response) {
    globalQueue.addAll(
      response.map((song) => MediaItemConverter().mapToMediaItem(song)),
    );
    fetched = true;
  }

  @override
  Widget build(BuildContext context) {
    BuildContext scaffoldContext;
    Map data = widget.data;
    if (response == data['response'] && globalIndex == data['index']) {
      same = true;
    }
    response = data['response'];
    globalIndex = data['index'];
    fromYT = data['fromYT'] ?? false;
    if (data['offline'] == null) {
      offline = AudioService.currentMediaItem?.extras['url'].startsWith('http')
          ? false
          : true;
    } else {
      offline = data['offline'];
    }
    if (!fetched) {
      if (response.length == 0 || same) {
        fromMiniplayer = true;
      } else {
        fromMiniplayer = false;
        if (!enforceRepeat) {
          repeatMode = 'None';
          Hive.box('settings').put('repeatMode', repeatMode);
        }
        shuffle = false;
        Hive.box('settings').put('shuffle', shuffle);
        AudioService.stop();
        if (offline) {
          setOffValues(response);
        } else {
          setValues(response);
        }
      }
    }

    Widget container = GradientContainer(
      child: SafeArea(
        child: StreamBuilder<QueueState>(
            stream: _queueStateStream,
            builder: (context, snapshot) {
              final queueState = snapshot.data;
              final queue = queueState?.queue ?? [];
              final mediaItem = queueState?.mediaItem;
              // if (queue.isNotEmpty && mediaItem != null)
              //   try {
              //     int newIndex =
              //         queue.indexWhere((element) => element == mediaItem);
              //     if (oldIndex != newIndex) {
              //       _controller.jumpToPage(newIndex);
              //       oldIndex = newIndex;
              //     }
              //     // });
              //   } catch (e) {}
              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  toolbarHeight: 40.0,
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  centerTitle: true,
                  leading: IconButton(
                      icon: Icon(Icons.expand_more_rounded),
                      color: Theme.of(context).iconTheme.color,
                      tooltip: 'Back',
                      onPressed: () {
                        if (widget.fromMiniplayer) {
                          widget.controller
                              .animateToHeight(state: PanelState.MIN);
                        } else {
                          Navigator.pop(context);
                        }
                      }),
                  actions: [
                    PopupMenuButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(7.0))),
                      onSelected: (value) {
                        if (value == 4) {
                          showDialog(
                              context: context,
                              builder: (context) {
                                return Equalizer();
                              });
                        }
                        if (value == 3) {
                          launch(fromYT
                              ? 'https://youtube.com/watch?v=${mediaItem.id}'
                              : 'https://www.youtube.com/results?search_query=${mediaItem.title} by ${mediaItem.artist}');
                        }
                        if (value == 2) {
                          offline
                              ? showModalBottomSheet(
                                  isDismissible: true,
                                  backgroundColor: Colors.transparent,
                                  context: context,
                                  builder: (BuildContext context) {
                                    return BottomGradientContainer(
                                      padding: EdgeInsets.zero,
                                      child: Center(
                                        child: SingleChildScrollView(
                                          physics: BouncingScrollPhysics(),
                                          padding: EdgeInsets.fromLTRB(
                                              10, 30, 10, 30),
                                          child: FutureBuilder(
                                              future: Lyrics().getOffLyrics(
                                                mediaItem.id.toString(),
                                              ),
                                              builder: (BuildContext context,
                                                  AsyncSnapshot snapshot) {
                                                if (snapshot.connectionState ==
                                                    ConnectionState.done) {
                                                  String lyrics = snapshot.data;
                                                  if (lyrics == '') {
                                                    return EmptyScreen()
                                                        .emptyScreen(
                                                            context,
                                                            0,
                                                            ":( ",
                                                            100.0,
                                                            "Lyrics",
                                                            60.0,
                                                            "Not Available",
                                                            20.0);
                                                  }
                                                  return SelectableText(
                                                    lyrics,
                                                    textAlign: TextAlign.center,
                                                  );
                                                }
                                                return CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                              Color>(
                                                          Theme.of(context)
                                                              .accentColor),
                                                );
                                              }),
                                        ),
                                      ),
                                    );
                                  })
                              : showModalBottomSheet(
                                  isDismissible: true,
                                  backgroundColor: Colors.transparent,
                                  context: context,
                                  builder: (BuildContext context) {
                                    String lyrics;
                                    final queueState = snapshot.data;
                                    final mediaItem = queueState?.mediaItem;

                                    return mediaItem == null
                                        ? SizedBox()
                                        : BottomGradientContainer(
                                            padding: EdgeInsets.zero,
                                            child: Center(
                                              child: SingleChildScrollView(
                                                physics:
                                                    BouncingScrollPhysics(),
                                                padding: EdgeInsets.fromLTRB(
                                                    10, 30, 10, 30),
                                                child: mediaItem.extras["has_lyrics"] ==
                                                        "true"
                                                    ? FutureBuilder(
                                                        future: Lyrics()
                                                            .getSaavnLyrics(
                                                                mediaItem.id
                                                                    .toString()),
                                                        builder:
                                                            (BuildContext context,
                                                                AsyncSnapshot
                                                                    snapshot) {
                                                          if (snapshot
                                                                  .connectionState ==
                                                              ConnectionState
                                                                  .done) {
                                                            lyrics =
                                                                snapshot.data;

                                                            return SelectableText(
                                                              lyrics,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            );
                                                          }
                                                          return CircularProgressIndicator(
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                    Color>(Theme.of(
                                                                        context)
                                                                    .accentColor),
                                                          );
                                                        })
                                                    : FutureBuilder(
                                                        future: Lyrics().getLyrics(
                                                            mediaItem.title
                                                                .toString(),
                                                            mediaItem.artist
                                                                .toString()),
                                                        builder:
                                                            (BuildContext context,
                                                                AsyncSnapshot
                                                                    snapshot) {
                                                          if (snapshot
                                                                  .connectionState ==
                                                              ConnectionState
                                                                  .done) {
                                                            String lyrics =
                                                                snapshot.data;
                                                            if (lyrics == '') {
                                                              return EmptyScreen()
                                                                  .emptyScreen(
                                                                      context,
                                                                      0,
                                                                      ":( ",
                                                                      100.0,
                                                                      "Lyrics",
                                                                      60.0,
                                                                      "Not Available",
                                                                      20.0);
                                                            }
                                                            return SelectableText(
                                                              lyrics,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            );
                                                          }
                                                          return CircularProgressIndicator(
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                    Color>(Theme.of(
                                                                        context)
                                                                    .accentColor),
                                                          );
                                                        }),
                                              ),
                                            ),
                                          );
                                  },
                                );
                        }
                        if (value == 1) {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return SimpleDialog(
                                title: Text(
                                  'Sleep Timer',
                                  style: TextStyle(
                                    color: Theme.of(context).accentColor,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.all(10.0),
                                children: [
                                  ListTile(
                                    title:
                                        Text('Sleep after a duration of hh:mm'),
                                    subtitle: Text(
                                        'Music will stop after selected duration'),
                                    dense: true,
                                    onTap: () {
                                      Navigator.pop(context);
                                      setTimer(context, scaffoldContext);
                                    },
                                  ),
                                  ListTile(
                                    title: Text('Sleep after N Songs'),
                                    subtitle: Text(
                                        'Music will stop after playing selected no of songs'),
                                    dense: true,
                                    onTap: () {
                                      Navigator.pop(context);
                                      setCounter(scaffoldContext);
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        }
                        if (value == 0) {
                          AddToPlaylist().addToPlaylist(context, mediaItem);
                        }
                      },
                      itemBuilder: (context) => offline
                          ? [
                              PopupMenuItem(
                                  value: 1,
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.timer,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text('Sleep Timer'),
                                      Spacer(),
                                    ],
                                  )),
                              PopupMenuItem(
                                  value: 2,
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.textformat,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text('Show Lyrics'),
                                      Spacer(),
                                    ],
                                  )),
                              PopupMenuItem(
                                  value: 4,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.equalizer_rounded,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text('Equalizer'),
                                      Spacer(),
                                    ],
                                  )),
                            ]
                          : [
                              PopupMenuItem(
                                  value: 0,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.playlist_add_rounded,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text('Add to playlist'),
                                      Spacer(),
                                    ],
                                  )),
                              PopupMenuItem(
                                  value: 1,
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.timer,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text('Sleep Timer'),
                                      Spacer(),
                                    ],
                                  )),
                              PopupMenuItem(
                                  value: 2,
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.textformat,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text('Show Lyrics'),
                                      Spacer(),
                                    ],
                                  )),
                              PopupMenuItem(
                                  value: 4,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.equalizer_rounded,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text('Equalizer'),
                                      Spacer(),
                                    ],
                                  )),
                              PopupMenuItem(
                                  value: 3,
                                  child: Row(
                                    children: [
                                      Icon(
                                        MdiIcons.youtube,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      Spacer(),
                                      Text(fromYT
                                          ? 'Watch Video'
                                          : 'Search Video'),
                                      Spacer(),
                                    ],
                                  )),
                            ],
                    )
                  ],
                ),
                body: Builder(builder: (BuildContext context) {
                  scaffoldContext = context;
                  return StreamBuilder<bool>(
                      stream: AudioService.runningStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState !=
                            ConnectionState.active) {
                          return SizedBox();
                        }
                        final running = snapshot.data ?? false;
                        return (!running)
                            ? FutureBuilder(
                                future: audioPlayerButton(),
                                builder: (context, AsyncSnapshot spshot) {
                                  if (spshot.hasData) {
                                    return SizedBox();
                                  } else {
                                    return Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        Container(
                                          height: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.9,
                                          child: Align(
                                            alignment: Alignment.topCenter,
                                            child: Container(
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.85,
                                              width: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.85,
                                              child: Card(
                                                elevation: 10,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            15)),
                                                clipBehavior: Clip.antiAlias,
                                                child: Container(
                                                  height: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.85,
                                                  width: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.85,
                                                  child: Stack(
                                                    children: [
                                                      Image(
                                                          fit: BoxFit.cover,
                                                          height: MediaQuery.of(
                                                                      context)
                                                                  .size
                                                                  .width *
                                                              0.85,
                                                          image: AssetImage(
                                                              'assets/cover.jpg')),
                                                      globalQueue.length <=
                                                              globalIndex
                                                          ? Image(
                                                              fit: BoxFit.cover,
                                                              height: MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.85,
                                                              image: AssetImage(
                                                                  'assets/cover.jpg'))
                                                          : offline
                                                              ? Image(
                                                                  fit:
                                                                      BoxFit
                                                                          .cover,
                                                                  height: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.85,
                                                                  width: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.85,
                                                                  image:
                                                                      FileImage(
                                                                          File(
                                                                    globalQueue[
                                                                            globalIndex]
                                                                        .artUri
                                                                        .toFilePath(),
                                                                  )))
                                                              : CachedNetworkImage(
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  height: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.85,
                                                                  errorWidget:
                                                                      (BuildContext context,
                                                                              _,
                                                                              __) =>
                                                                          Image(
                                                                    image: AssetImage(
                                                                        'assets/cover.jpg'),
                                                                  ),
                                                                  placeholder:
                                                                      (BuildContext context,
                                                                              _) =>
                                                                          Image(
                                                                    image: AssetImage(
                                                                        'assets/cover.jpg'),
                                                                  ),
                                                                  imageUrl: globalQueue[
                                                                          globalIndex]
                                                                      .artUri
                                                                      .toString(),
                                                                ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          height: (MediaQuery.of(context)
                                                          .size
                                                          .height *
                                                      0.875 -
                                                  MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.925) *
                                              1 /
                                              4.5,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                35, 5, 35, 0),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                Expanded(
                                                  flex: 5,
                                                  child: FittedBox(
                                                    child: Text(
                                                      globalQueue.length <=
                                                              globalIndex
                                                          ? 'Unknown'
                                                          : globalQueue[
                                                                  globalIndex]
                                                              .title
                                                              .split(" (")[0]
                                                              .split("|")[0]
                                                              .trim(),
                                                      textAlign:
                                                          TextAlign.center,
                                                      overflow:
                                                          TextOverflow.fade,
                                                      maxLines: 1,
                                                      style: TextStyle(
                                                          fontSize: 45,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Theme.of(context)
                                                                  .accentColor),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    globalQueue.length <=
                                                            globalIndex
                                                        ? 'Unknown'
                                                        : globalQueue[
                                                                globalIndex]
                                                            .artist,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w500),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        SeekBar(
                                          duration: Duration.zero,
                                          position: Duration.zero,
                                          bufferedPosition: Duration.zero,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5.0),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceAround,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Column(
                                                children: [
                                                  SizedBox(height: 6.0),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.shuffle_rounded,
                                                    ),
                                                    tooltip: 'Shuffle',
                                                    iconSize: 25.0,
                                                    onPressed: null,
                                                  ),
                                                  if (!offline)
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons
                                                            .favorite_border_rounded,
                                                      ),
                                                      tooltip: 'Like',
                                                      iconSize: 25.0,
                                                      onPressed: null,
                                                    ),
                                                ],
                                              ),
                                              IconButton(
                                                icon: Icon(Icons
                                                    .skip_previous_rounded),
                                                tooltip: 'Skip Previous',
                                                iconSize: 45.0,
                                                onPressed: null,
                                              ),
                                              Stack(
                                                children: [
                                                  Center(
                                                      child: SizedBox(
                                                    height: 65,
                                                    width: 65,
                                                    child:
                                                        CircularProgressIndicator(
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              Theme.of(context)
                                                                  .accentColor),
                                                    ),
                                                  )),
                                                  Center(
                                                    child: Container(
                                                      height: 65,
                                                      width: 65,
                                                      child: Center(
                                                        child: SizedBox(
                                                          height: 59,
                                                          width: 59,
                                                          child: playButton(),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              IconButton(
                                                icon: Icon(
                                                    Icons.skip_next_rounded),
                                                iconSize: 45.0,
                                                tooltip: 'Skip Next',
                                                onPressed: null,
                                              ),
                                              Column(
                                                children: [
                                                  SizedBox(height: 6.0),
                                                  IconButton(
                                                    icon: Icon(
                                                        Icons.repeat_rounded),
                                                    iconSize: 25.0,
                                                    tooltip: 'Repeat',
                                                    onPressed: null,
                                                  ),
                                                  if (!offline)
                                                    IconButton(
                                                        icon: Icon(
                                                            Icons.save_alt),
                                                        iconSize: 25.0,
                                                        tooltip: 'Download',
                                                        onPressed: null),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          height: 45,
                                        ),
                                      ],
                                    );
                                  }
                                })
                            : Stack(
                                children: [
                                  Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Container(
                                        height:
                                            MediaQuery.of(context).size.width *
                                                0.9,
                                        child: (mediaItem == null ||
                                                queue.isEmpty)
                                            ? Align(
                                                alignment: Alignment.topCenter,
                                                child: Container(
                                                  height: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.85,
                                                  width: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.85,
                                                  child: Card(
                                                    elevation: 10.0,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        15.0)),
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    child: Stack(
                                                      children: [
                                                        Image(
                                                            fit: BoxFit.cover,
                                                            height: MediaQuery.of(
                                                                        context)
                                                                    .size
                                                                    .width *
                                                                0.85,
                                                            image: AssetImage(
                                                                'assets/cover.jpg')),
                                                        (globalQueue.length >
                                                                globalIndex)
                                                            ? offline
                                                                ? Image(
                                                                    fit: BoxFit
                                                                        .cover,
                                                                    height: MediaQuery.of(context)
                                                                            .size
                                                                            .width *
                                                                        0.85,
                                                                    width: MediaQuery.of(context)
                                                                            .size
                                                                            .width *
                                                                        0.85,
                                                                    image:
                                                                        FileImage(
                                                                            File(
                                                                      globalQueue[
                                                                              globalIndex]
                                                                          .artUri
                                                                          .toFilePath(),
                                                                    )))
                                                                : CachedNetworkImage(
                                                                    fit: BoxFit
                                                                        .cover,
                                                                    errorWidget:
                                                                        (BuildContext context,
                                                                                _,
                                                                                __) =>
                                                                            Image(
                                                                      image: AssetImage(
                                                                          'assets/cover.jpg'),
                                                                    ),
                                                                    placeholder:
                                                                        (BuildContext context,
                                                                                _) =>
                                                                            Image(
                                                                      image: AssetImage(
                                                                          'assets/cover.jpg'),
                                                                    ),
                                                                    imageUrl: globalQueue[
                                                                            globalIndex]
                                                                        .artUri
                                                                        .toString(),
                                                                    height: MediaQuery.of(context)
                                                                            .size
                                                                            .width *
                                                                        0.85,
                                                                  )
                                                            : SizedBox()
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              )
                                            :
                                            // PageView.builder(
                                            //     controller: _controller,
                                            //     itemCount:
                                            //         repeatMode != 'All'
                                            //             ? queue.length
                                            //             : null,
                                            //     scrollBehavior:
                                            //         ScrollBehavior(),
                                            //     onPageChanged: (indx) {
                                            //       if (queue.isNotEmpty &&
                                            //           mediaItem != null) {
                                            //         if (repeatMode ==
                                            //                 'All' ||
                                            //             queue[indx] !=
                                            //                 mediaItem) {
                                            //           AudioService
                                            //           .skipToQueueItem(
                                            //               queue[indx %
                                            //                       queue
                                            //                           .length]
                                            //                   .id);
                                            //     }
                                            //   }
                                            // },
                                            // physics:
                                            //     BouncingScrollPhysics(),
                                            // itemBuilder:
                                            //     (context, index) =>
                                            GestureDetector(
                                                onTap: () {
                                                  if (AudioService.playbackState
                                                          .playing ==
                                                      true) {
                                                    AudioService.pause();
                                                  } else {
                                                    AudioService.play();
                                                  }
                                                },
                                                child: Align(
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: Container(
                                                    height:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.85,
                                                    width:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.85,
                                                    child: Card(
                                                      elevation: 10.0,
                                                      shape:
                                                          RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          15.0)),
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      child: Stack(
                                                        children: [
                                                          Image(
                                                              fit: BoxFit.cover,
                                                              height: MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.85,
                                                              image: AssetImage(
                                                                  'assets/cover.jpg')),
                                                          offline
                                                              ? Image(
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  height: MediaQuery.of(context)
                                                                          .size
                                                                          .width *
                                                                      0.85,
                                                                  width: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.85,
                                                                  image: FileImage(File(mediaItem
                                                                      // queue[index %
                                                                      // queue.length]
                                                                      .artUri
                                                                      .toFilePath())))
                                                              : CachedNetworkImage(
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  errorWidget:
                                                                      (BuildContext context,
                                                                              _,
                                                                              __) =>
                                                                          Image(
                                                                    image: AssetImage(
                                                                        'assets/cover.jpg'),
                                                                  ),
                                                                  placeholder:
                                                                      (BuildContext context,
                                                                              _) =>
                                                                          Image(
                                                                    image: AssetImage(
                                                                        'assets/cover.jpg'),
                                                                  ),
                                                                  imageUrl: mediaItem
                                                                      // queue[index %
                                                                      // queue.length]
                                                                      .artUri
                                                                      .toString(),
                                                                  height: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.85,
                                                                )
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                      // ),

                                      /// Title and subtitle
                                      Container(
                                        height: (MediaQuery.of(context)
                                                        .size
                                                        .height *
                                                    0.875 -
                                                MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.925) *
                                            1 /
                                            4.5,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              35, 5, 35, 0),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              /// Title container
                                              Expanded(
                                                flex: 5,
                                                child: FittedBox(
                                                  child: Text(
                                                    (mediaItem?.title != null)
                                                        ? (mediaItem.title
                                                            .split(" (")[0]
                                                            .split("|")[0]
                                                            .trim())
                                                        : ((globalQueue
                                                                    .length <=
                                                                globalIndex)
                                                            ? 'Title'
                                                            : globalQueue[
                                                                    globalIndex]
                                                                .title
                                                                .split(" (")[0]
                                                                .split("|")[0]
                                                                .trim()),
                                                    textAlign: TextAlign.center,
                                                    overflow: TextOverflow.fade,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                        fontSize: 45,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Theme.of(context)
                                                            .accentColor),
                                                  ),
                                                ),
                                              ),

                                              /// Subtitle container
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  (mediaItem?.artist != null)
                                                      ? (mediaItem.artist)
                                                      : ((globalQueue.length <=
                                                              globalIndex)
                                                          ? ''
                                                          : globalQueue[
                                                                  globalIndex]
                                                              .artist),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w500),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      /// Seekbar starts from here
                                      StreamBuilder<MediaState>(
                                        stream: _mediaStateStream,
                                        builder: (context, snapshot) {
                                          final mediaState = snapshot.data;
                                          return SeekBar(
                                            duration: mediaState
                                                    ?.mediaItem?.duration ??
                                                Duration.zero,
                                            position: mediaState?.position ??
                                                Duration.zero,
                                            bufferedPosition:
                                                mediaState?.bufferPosition ??
                                                    Duration.zero,
                                            onChangeEnd: (newPosition) {
                                              AudioService.seekTo(newPosition);
                                            },
                                          );
                                        },
                                      ),

                                      /// Final row starts from here
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceAround,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Column(
                                              children: [
                                                SizedBox(height: 6.0),
                                                IconButton(
                                                  icon: Icon(
                                                      Icons.shuffle_rounded),
                                                  iconSize: 25.0,
                                                  tooltip: 'Shuffle',
                                                  color: shuffle
                                                      ? Theme.of(context)
                                                          .accentColor
                                                      : null,
                                                  onPressed: () {
                                                    shuffle = !shuffle;
                                                    Hive.box('settings').put(
                                                        'shuffle', shuffle);
                                                    if (shuffle)
                                                      AudioService.setShuffleMode(
                                                          AudioServiceShuffleMode
                                                              .all);
                                                    else
                                                      AudioService.setShuffleMode(
                                                          AudioServiceShuffleMode
                                                              .none);
                                                  },
                                                ),
                                                if (!offline)
                                                  mediaItem == null
                                                      ? IconButton(
                                                          icon: Icon(Icons
                                                              .favorite_border_rounded),
                                                          iconSize: 25.0,
                                                          tooltip: 'Like',
                                                          onPressed: null)
                                                      : LikeButton(
                                                          mediaItem: mediaItem,
                                                          size: 25.0)
                                              ],
                                            ),
                                            (queue.isNotEmpty)
                                                ? IconButton(
                                                    icon: Icon(Icons
                                                        .skip_previous_rounded),
                                                    iconSize: 45.0,
                                                    tooltip: 'Skip Previous',
                                                    onPressed: (mediaItem !=
                                                                null &&
                                                            (mediaItem !=
                                                                    queue
                                                                        .first ||
                                                                repeatMode ==
                                                                    'All'))
                                                        ? () {
                                                            if (mediaItem ==
                                                                queue.first) {
                                                              AudioService
                                                                  .skipToQueueItem(
                                                                      queue.last
                                                                          .id);
                                                            } else {
                                                              AudioService
                                                                  .skipToPrevious();
                                                            }
                                                          }
                                                        : null)
                                                : IconButton(
                                                    icon: Icon(Icons
                                                        .skip_previous_rounded),
                                                    iconSize: 45.0,
                                                    tooltip: 'Skip Previous',
                                                    onPressed: null),

                                            /// Play button
                                            Stack(
                                              children: [
                                                Center(
                                                  child: StreamBuilder<
                                                      AudioProcessingState>(
                                                    stream: AudioService
                                                        .playbackStateStream
                                                        .map((state) => state
                                                            .processingState)
                                                        .distinct(),
                                                    builder:
                                                        (context, snapshot) {
                                                      final processingState =
                                                          snapshot.data ??
                                                              AudioProcessingState
                                                                  .none;
                                                      return describeEnum(
                                                                  processingState) !=
                                                              'ready'
                                                          ? SizedBox(
                                                              height: 65,
                                                              width: 65,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                valueColor: AlwaysStoppedAnimation<
                                                                    Color>(Theme.of(
                                                                        context)
                                                                    .accentColor),
                                                              ),
                                                            )
                                                          : SizedBox();
                                                    },
                                                  ),
                                                ),
                                                Center(
                                                  child: StreamBuilder<bool>(
                                                    stream: AudioService
                                                        .playbackStateStream
                                                        .map((state) =>
                                                            state.playing)
                                                        .distinct(),
                                                    builder:
                                                        (context, snapshot) {
                                                      final playing =
                                                          snapshot.data ??
                                                              false;
                                                      return Container(
                                                        height: 65,
                                                        width: 65,
                                                        child: Center(
                                                          child: SizedBox(
                                                            height: 59,
                                                            width: 59,
                                                            child: playing
                                                                ? pauseButton()
                                                                : playButton(),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),

                                            (queue.isNotEmpty)
                                                ? IconButton(
                                                    icon: Icon(Icons
                                                        .skip_next_rounded),
                                                    iconSize: 45.0,
                                                    tooltip: 'Skip Next',
                                                    onPressed: (mediaItem !=
                                                                null &&
                                                            (mediaItem !=
                                                                    queue
                                                                        .last ||
                                                                repeatMode ==
                                                                    'All'))
                                                        ? () {
                                                            if (mediaItem ==
                                                                queue.last) {
                                                              AudioService
                                                                  .skipToQueueItem(
                                                                      queue
                                                                          .first
                                                                          .id);
                                                            } else {
                                                              AudioService
                                                                  .skipToNext();
                                                            }
                                                          }
                                                        : null)
                                                : IconButton(
                                                    icon: Icon(Icons
                                                        .skip_next_rounded),
                                                    iconSize: 45.0,
                                                    tooltip: 'Skip Next',
                                                    onPressed: null),

                                            Column(
                                              children: [
                                                SizedBox(height: 6.0),
                                                IconButton(
                                                  icon: repeatMode == 'One'
                                                      ? Icon(Icons
                                                          .repeat_one_rounded)
                                                      : Icon(
                                                          Icons.repeat_rounded),
                                                  iconSize: 25.0,
                                                  tooltip: 'Repeat $repeatMode',
                                                  color: repeatMode == 'None'
                                                      ? null
                                                      : Theme.of(context)
                                                          .accentColor,
                                                  // Icons.repeat_one_rounded
                                                  onPressed: () {
                                                    switch (repeatMode) {
                                                      case 'None':
                                                        repeatMode = 'All';
                                                        AudioService.setRepeatMode(
                                                            AudioServiceRepeatMode
                                                                .all);
                                                        break;
                                                      case 'All':
                                                        repeatMode = 'One';
                                                        AudioService.setRepeatMode(
                                                            AudioServiceRepeatMode
                                                                .one);
                                                        break;
                                                      case 'One':
                                                        repeatMode = 'None';
                                                        AudioService.setRepeatMode(
                                                            AudioServiceRepeatMode
                                                                .none);
                                                        break;
                                                      default:
                                                        break;
                                                    }
                                                    Hive.box('settings').put(
                                                        'repeatMode',
                                                        repeatMode);

                                                    setState(() {});
                                                  },
                                                ),
                                                if (!offline)
                                                  (mediaItem != null &&
                                                          queue.isNotEmpty)
                                                      ? DownloadButton(data: {
                                                          'id': mediaItem.id
                                                              .toString(),
                                                          'artist': mediaItem
                                                              .artist
                                                              .toString(),
                                                          'album': mediaItem
                                                              .album
                                                              .toString(),
                                                          'image': mediaItem
                                                              .artUri
                                                              .toString(),
                                                          'duration': mediaItem
                                                              .duration
                                                              .inSeconds
                                                              .toString(),
                                                          'title': mediaItem
                                                              .title
                                                              .toString(),
                                                          'url': mediaItem
                                                              .extras['url']
                                                              .toString(),
                                                          "year": mediaItem
                                                              .extras["year"]
                                                              .toString(),
                                                          "language": mediaItem
                                                              .extras[
                                                                  "language"]
                                                              .toString(),
                                                          "genre": mediaItem
                                                              .genre
                                                              .toString(),
                                                          "320kbps":
                                                              mediaItem.extras[
                                                                  "320kbps"],
                                                          "has_lyrics":
                                                              mediaItem.extras[
                                                                  "has_lyrics"],
                                                          "release_date":
                                                              mediaItem.extras[
                                                                  "release_date"],
                                                          "album_id":
                                                              mediaItem.extras[
                                                                  "album_id"],
                                                          "subtitle":
                                                              mediaItem.extras[
                                                                  "subtitle"]
                                                        })
                                                      : IconButton(
                                                          icon: Icon(
                                                            Icons.save_alt,
                                                          ),
                                                          iconSize: 25.0,
                                                          tooltip: 'Download',
                                                          onPressed: null),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        height: 45,
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: SizedBox(
                                      height: 500,
                                      width: MediaQuery.of(context).size.width *
                                          0.95,
                                      child: DraggableScrollableActuator(
                                        child: DraggableScrollableSheet(
                                            key: Key(initialExtent.toString()),
                                            minChildSize: minExtent,
                                            maxChildSize: maxExtent,
                                            initialChildSize: initialExtent,
                                            builder: (BuildContext dragContext,
                                                ScrollController
                                                    scrollController) {
                                              return BottomGradientContainer(
                                                padding: EdgeInsets.zero,
                                                margin: EdgeInsets.only(
                                                    left: 20, right: 20),
                                                borderRadius: BorderRadius.only(
                                                    topLeft:
                                                        Radius.circular(15.0),
                                                    topRight:
                                                        Radius.circular(15.0)),
                                                child: (mediaItem == null ||
                                                        queue.isEmpty)
                                                    ? SizedBox()
                                                    : ReorderableListView
                                                        .builder(
                                                            header: SizedBox(
                                                              key: Key('head'),
                                                              height: 50,
                                                              child: Center(
                                                                child: SizedBox
                                                                    .expand(
                                                                  child: TextButton(
                                                                      style: TextButton.styleFrom(
                                                                        primary: Theme.of(context)
                                                                            .iconTheme
                                                                            .color,
                                                                        backgroundColor:
                                                                            Colors.transparent,
                                                                        elevation:
                                                                            0.0,
                                                                      ),
                                                                      child: Text(
                                                                        'Now Playing',
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        style:
                                                                            TextStyle(
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                          fontSize:
                                                                              18,
                                                                        ),
                                                                      ),
                                                                      onPressed: () {
                                                                        setState(
                                                                            () {
                                                                          initialExtent = isExpanded
                                                                              ? minExtent
                                                                              : maxExtent;
                                                                          isExpanded =
                                                                              !isExpanded;
                                                                        });
                                                                        DraggableScrollableActuator.reset(
                                                                            dragContext);
                                                                      }),
                                                                ),
                                                              ),
                                                            ),
                                                            scrollController:
                                                                scrollController,
                                                            onReorder: (int
                                                                    oldIndex,
                                                                int newIndex) {
                                                              setState(() {
                                                                if (oldIndex <
                                                                    newIndex)
                                                                  newIndex--;
                                                                final items =
                                                                    queue.removeAt(
                                                                        oldIndex);
                                                                queue.insert(
                                                                    newIndex,
                                                                    items);
                                                                AudioService
                                                                    .customAction(
                                                                        'reorder',
                                                                        [
                                                                      oldIndex,
                                                                      newIndex
                                                                    ]);
                                                              });
                                                            },
                                                            physics:
                                                                BouncingScrollPhysics(),
                                                            padding:
                                                                EdgeInsets.only(
                                                                    top: 0,
                                                                    bottom: 10),
                                                            shrinkWrap: true,
                                                            itemCount:
                                                                queue.length,
                                                            itemBuilder:
                                                                (context,
                                                                    index) {
                                                              return Dismissible(
                                                                key: Key(
                                                                    queue[index]
                                                                        .id),
                                                                direction: queue[
                                                                            index] ==
                                                                        mediaItem
                                                                    ? DismissDirection
                                                                        .none
                                                                    : DismissDirection
                                                                        .horizontal,
                                                                onDismissed:
                                                                    (dir) {
                                                                  setState(() {
                                                                    AudioService
                                                                        .removeQueueItem(
                                                                            queue[index]);
                                                                    queue.remove(
                                                                        queue[
                                                                            index]);
                                                                  });
                                                                },
                                                                child:
                                                                    ListTileTheme(
                                                                  selectedColor:
                                                                      Theme.of(
                                                                              context)
                                                                          .accentColor,
                                                                  child:
                                                                      ListTile(
                                                                    contentPadding: EdgeInsets.only(
                                                                        left:
                                                                            16.0,
                                                                        right:
                                                                            10.0),
                                                                    selected: queue[
                                                                            index] ==
                                                                        mediaItem,
                                                                    trailing: queue[index] ==
                                                                            mediaItem
                                                                        ? IconButton(
                                                                            icon:
                                                                                Icon(
                                                                              Icons.bar_chart_rounded,
                                                                            ),
                                                                            tooltip:
                                                                                'Playing',
                                                                            onPressed:
                                                                                () {},
                                                                          )
                                                                        : offline
                                                                            ? SizedBox()
                                                                            : Row(
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                children: [
                                                                                  LikeButton(
                                                                                    mediaItem: queue[index],
                                                                                  ),
                                                                                  DownloadButton(icon: 'download', data: {
                                                                                    'id': queue[index].id.toString(),
                                                                                    'artist': queue[index].artist.toString(),
                                                                                    'album': queue[index].album.toString(),
                                                                                    'image': queue[index].artUri.toString(),
                                                                                    'duration': queue[index].duration.inSeconds.toString(),
                                                                                    'title': queue[index].title.toString(),
                                                                                    'url': queue[index].extras['url'].toString(),
                                                                                    "year": queue[index].extras["year"].toString(),
                                                                                    "language": queue[index].extras["language"].toString(),
                                                                                    "genre": queue[index].genre.toString(),
                                                                                    "320kbps": queue[index].extras["320kbps"],
                                                                                    "has_lyrics": queue[index].extras["has_lyrics"],
                                                                                    "release_date": queue[index].extras["release_date"],
                                                                                    "album_id": queue[index].extras["album_id"],
                                                                                    "subtitle": queue[index].extras["subtitle"]
                                                                                  })
                                                                                ],
                                                                              ),
                                                                    leading:
                                                                        Card(
                                                                      elevation:
                                                                          5,
                                                                      shape:
                                                                          RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(7.0),
                                                                      ),
                                                                      clipBehavior:
                                                                          Clip.antiAlias,
                                                                      child:
                                                                          Stack(
                                                                        children: [
                                                                          Image(
                                                                            image:
                                                                                AssetImage('assets/cover.jpg'),
                                                                          ),
                                                                          queue[index].artUri == null
                                                                              ? SizedBox()
                                                                              : SizedBox(
                                                                                  height: 50.0,
                                                                                  width: 50.0,
                                                                                  child: queue[index].artUri.toString().startsWith('file:')
                                                                                      ? Image(fit: BoxFit.cover, image: FileImage(File(queue[index].artUri.toFilePath())))
                                                                                      : CachedNetworkImage(
                                                                                          fit: BoxFit.cover,
                                                                                          errorWidget: (BuildContext context, _, __) => Image(
                                                                                            image: AssetImage('assets/cover.jpg'),
                                                                                          ),
                                                                                          placeholder: (BuildContext context, _) => Image(
                                                                                            image: AssetImage('assets/cover.jpg'),
                                                                                          ),
                                                                                          imageUrl: queue[index].artUri.toString(),
                                                                                        ),
                                                                                ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                    title: Text(
                                                                      '${queue[index].title}',
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style: TextStyle(
                                                                          fontWeight: queue[index] == mediaItem
                                                                              ? FontWeight.w600
                                                                              : FontWeight.normal),
                                                                    ),
                                                                    subtitle:
                                                                        Text(
                                                                      '${queue[index].artist}',
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                    onTap: () {
                                                                      AudioService.skipToQueueItem(
                                                                          queue[index]
                                                                              .id);
                                                                    },
                                                                  ),
                                                                ),
                                                              );
                                                            }),
                                              );
                                            }),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                      });
                }),
              );
            }),
      ),
      // ),
    );
    return widget.fromMiniplayer
        ? container
        : Dismissible(
            direction: DismissDirection.down,
            background: Container(color: Colors.transparent),
            key: Key('playScreen'),
            onDismissed: (direction) {
              Navigator.pop(context);
            },
            child: container);
  }

  Future<dynamic> setTimer(BuildContext context, BuildContext scaffoldContext) {
    return showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Center(
              child: Text(
            'Select a Duration',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).accentColor),
          )),
          children: [
            Center(
                child: SizedBox(
              height: 200,
              width: 200,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  primaryColor: Theme.of(context).accentColor,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).accentColor,
                    ),
                  ),
                ),
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hm,
                  onTimerDurationChanged: (value) {
                    _time = value;
                  },
                ),
              ),
            )),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    primary: Theme.of(context).accentColor,
                  ),
                  child: Text('Cancel'),
                  onPressed: () {
                    sleepTimer(0);
                    Navigator.pop(context);
                  },
                ),
                SizedBox(
                  width: 10,
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    primary: Colors.white,
                    backgroundColor: Theme.of(context).accentColor,
                  ),
                  child: Text('Ok'),
                  onPressed: () {
                    sleepTimer(_time.inMinutes);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        duration: Duration(seconds: 2),
                        elevation: 6,
                        backgroundColor: Colors.grey[900],
                        behavior: SnackBarBehavior.floating,
                        content: Text(
                          'Sleep timer set for ${_time.inMinutes} minutes',
                          style: TextStyle(color: Colors.white),
                        ),
                        action: SnackBarAction(
                          textColor: Theme.of(context).accentColor,
                          label: 'Ok',
                          onPressed: () {},
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(
                  width: 20,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<dynamic> setCounter(
      BuildContext scaffoldContext) async {
    await TextInputDialog().showTextInputDialog(
        scaffoldContext, 'Enter no of Songs', '', TextInputType.number,
        (String value) {
      sleepCounter(int.parse(value));
      Navigator.pop(scaffoldContext);
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          duration: Duration(seconds: 2),
          elevation: 6,
          backgroundColor: Colors.grey[900],
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Sleep timer set for $value songs',
            style: TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            textColor: Theme.of(context).accentColor,
            label: 'Ok',
            onPressed: () {},
          ),
        ),
      );
    });
  }

  /// A stream reporting the combined state of the current media item and its
  /// current position.
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest3<MediaItem, Duration, Duration, MediaState>(
          AudioService.currentMediaItemStream,
          AudioService.positionStream,
          AudioService.playbackStateStream
              .map((state) => state.bufferedPosition)
              .distinct(),
          (mediaItem, position, bufferPosition) =>
              MediaState(mediaItem, position, bufferPosition));

  /// A stream reporting the combined state of the current queue and the current
  /// media item within that queue.
  Stream<QueueState> get _queueStateStream =>
      Rx.combineLatest2<List<MediaItem>, MediaItem, QueueState>(
          AudioService.queueStream,
          AudioService.currentMediaItemStream,
          (queue, mediaItem) => QueueState(queue, mediaItem));

  audioPlayerButton() async {
    await AudioService.start(
      backgroundTaskEntrypoint: _audioPlayerTaskEntrypoint,
      params: {
        'index': globalIndex,
        'offline': offline,
        'quality': preferredQuality
      },
      androidNotificationChannelName: 'BlackHole',
      androidNotificationColor: 0xFF181818,
      androidNotificationIcon: 'drawable/ic_stat_music_note',
      androidEnableQueue: true,
      androidStopForegroundOnPause: stopServiceOnPause,
    );

    await AudioService.updateQueue(globalQueue);
    // await AudioService.skipToQueueItem(globalQueue[globalIndex].id);
    await AudioService.play();
    if (enforceRepeat) {
      switch (repeatMode) {
        case 'None':
          AudioService.setRepeatMode(AudioServiceRepeatMode.none);
          break;
        case 'All':
          AudioService.setRepeatMode(AudioServiceRepeatMode.all);
          break;
        case 'One':
          AudioService.setRepeatMode(AudioServiceRepeatMode.one);
          break;
        default:
          break;
      }
    }
  }

  FloatingActionButton playButton() => FloatingActionButton(
        elevation: 10,
        tooltip: 'Play',
        child: Icon(
          Icons.play_arrow_rounded,
          size: 40.0,
          color: Colors.white,
        ),
        onPressed: AudioService.play,
      );

  FloatingActionButton pauseButton() => FloatingActionButton(
        elevation: 10,
        tooltip: 'Pause',
        child: Icon(
          Icons.pause_rounded,
          color: Colors.white,
          size: 40.0,
        ),
        onPressed: AudioService.pause,
      );
}

class QueueState {
  final List<MediaItem> queue;
  final MediaItem mediaItem;

  QueueState(this.queue, this.mediaItem);
}

class MediaState {
  final MediaItem mediaItem;
  final Duration position;
  final Duration bufferPosition;

  MediaState(this.mediaItem, this.position, this.bufferPosition);
}

void _audioPlayerTaskEntrypoint() async {
  AudioServiceBackground.run(() => AudioPlayerTask());
}
