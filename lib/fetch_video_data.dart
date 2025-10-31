import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:myapp/video_with_subtitle.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Model for video data
class VideoItem {
  final String hash;
  final String videoUrl;
  final String subtitleUrl;

  VideoItem({
    required this.hash,
    required this.videoUrl,
    required this.subtitleUrl,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      hash: json['hash'] ?? '',
      videoUrl: json['videoUrl'] ?? '',
      subtitleUrl: json['subtitleUrl'] ?? '',
    );
  }
}

// Function to fetch videos
Future<List<VideoItem>> fetchUserVideos() async {
  try {
    // Get userId from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userid');

    if (userId == null || userId.isEmpty) {
      throw Exception('User ID not found');
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    // Make GET request with userId as query parameter
    final response = await dio.get(
      'http://65.0.7.70:3000/list-videos',
      queryParameters: {'userId': userId},
    );

    if (response.statusCode == 200) {
      final data = response.data;
      final List<dynamic> videosJson = data['videos'] ?? [];

      return videosJson.map((json) => VideoItem.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load videos: ${response.statusCode}');
    }
  } catch (e) {
    print('Error fetching videos: $e');
    rethrow;
  }
}

// Video List Screen
class VideoListScreen extends StatefulWidget {
  const VideoListScreen({super.key});

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  List<VideoItem> _videos = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Load videos when screen initializes
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final videos = await fetchUserVideos();
      if (mounted) {
        setState(() {
          _videos = videos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Videos'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVideos,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading videos...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading videos',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadVideos,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _videos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.video_library_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No videos yet',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your processed videos will appear here',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _videos.length,
                      itemBuilder: (context, index) {
                        final video = _videos[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.play_circle_outline,
                                size: 32,
                                color: Colors.black54,
                              ),
                            ),
                            title: Text(
                              'Video ${video.hash}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Hash: ${video.hash}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.play_arrow),
                            onTap: () async {
                              // Show loading indicator
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              );

                              try {
                                // Fetch subtitle JSON data from the signed URL
                                final dio = Dio();
                                final subtitleResponse = await dio.get(
                                  video.subtitleUrl,
                                  options: Options(
                                    responseType: ResponseType.plain,
                                  ),
                                );

                                // Close loading dialog
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }

                                // Navigate to video player with fetched subtitle data
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VideoWithSubtitles(
                                        videoPath: video.videoUrl,
                                        sourceType: VideoSourceType.network,
                                        subtitleData: subtitleResponse.data.toString(),
                                        format: SubtitleFormat.json,
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                print('Error loading video/subtitles: $e');
                                
                                // Close loading dialog
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }

                                // Show error
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error loading video: $e'),
                                      backgroundColor: Colors.red,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}

// HOW TO USE THIS SCREEN:
// 
// In your app, navigate to this screen like this:
// 
// Navigator.push(
//   context,
//   MaterialPageRoute(
//     builder: (context) => const VideoListScreen(),
//   ),
// );
//
// The screen will automatically load videos when it opens (_loadVideos is called in initState)