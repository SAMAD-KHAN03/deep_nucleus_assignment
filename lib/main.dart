import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:myapp/stretchable_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  String? storedUuid = prefs.getString('userid');

  if (storedUuid == null) {
    storedUuid = Uuid().v4();
    await prefs.setString("userid", storedUuid);
  } else {
    log("found the uuid: $storedUuid");
  }

  // Load subtitles JSON safely
  // ignore: unused_local_variable
  final subtitleJson = jsonEncode({
  "audio_segments": [
    {
      "id": 0,
      "transcript": "Welcome to our fitness tutorial!",
      "start_time": "0.0",
      "end_time": "2.5",
      "items": [0, 1, 2, 3, 4]
    },
    {
      "id": 1,
      "transcript": "Today we're going to learn proper squat form.",
      "start_time": "3.0",
      "end_time": "6.5",
      "items": [5, 6, 7, 8, 9, 10, 11, 12]
    },
    {
      "id": 2,
      "transcript": "The most important thing is keeping your back straight.",
      "start_time": "7.0",
      "end_time": "10.8",
      "items": [13, 14, 15, 16, 17, 18, 19, 20, 21]
    },
    {
      "id": 3,
      "transcript": "Don't lean forward. Keep your nose pointing straight down.",
      "start_time": "11.2",
      "end_time": "15.5",
      "items": [22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
    },
    {
      "id": 4,
      "transcript": "Think of it like jumping into water, not diving.",
      "start_time": "16.0",
      "end_time": "19.3",
      "items": [32, 33, 34, 35, 36, 37, 38, 39, 40]
    },
    {
      "id": 5,
      "transcript": "Your knees should track over your toes.",
      "start_time": "20.0",
      "end_time": "23.2",
      "items": [41, 42, 43, 44, 45, 46, 47]
    },
    {
      "id": 6,
      "transcript": "Keep your core engaged throughout the movement.",
      "start_time": "23.8",
      "end_time": "27.1",
      "items": [48, 49, 50, 51, 52, 53, 54]
    },
    {
      "id": 7,
      "transcript": "Breathe in on the way down, exhale on the way up.",
      "start_time": "27.5",
      "end_time": "31.8",
      "items": [55, 56, 57, 58, 59, 60, 61, 62, 63, 64]
    },
    {
      "id": 8,
      "transcript": "Start with bodyweight squats before adding weight.",
      "start_time": "32.2",
      "end_time": "35.9",
      "items": [65, 66, 67, 68, 69, 70, 71]
    },
    {
      "id": 9,
      "transcript": "Quality over quantity. Focus on perfect form.",
      "start_time": "36.5",
      "end_time": "40.2",
      "items": [72, 73, 74, 75, 76, 77, 78]
    },
    {
      "id": 10,
      "transcript": "Let's do three sets of ten repetitions.",
      "start_time": "40.8",
      "end_time": "44.1",
      "items": [79, 80, 81, 82, 83, 84, 85]
    },
    {
      "id": 11,
      "transcript": "Remember to warm up before you start.",
      "start_time": "44.6",
      "end_time": "47.5",
      "items": [86, 87, 88, 89, 90, 91]
    },
    {
      "id": 12,
      "transcript": "Great job! You're doing excellent.",
      "start_time": "48.0",
      "end_time": "50.8",
      "items": [92, 93, 94, 95, 96]
    },
    {
      "id": 13,
      "transcript": "Keep your chest up and shoulders back.",
      "start_time": "51.3",
      "end_time": "54.7",
      "items": [97, 98, 99, 100, 101, 102]
    },
    {
      "id": 14,
      "transcript": "Feel the burn in your quadriceps.",
      "start_time": "55.2",
      "end_time": "58.0",
      "items": [103, 104, 105, 106, 107]
    },
    {
      "id": 15,
      "transcript": "This exercise builds strength and stability.",
      "start_time": "58.5",
      "end_time": "62.1",
      "items": [108, 109, 110, 111, 112, 113]
    },
    {
      "id": 16,
      "transcript": "Don't forget to stretch after your workout.",
      "start_time": "62.6",
      "end_time": "66.2",
      "items": [114, 115, 116, 117, 118, 119, 120]
    },
    {
      "id": 17,
      "transcript": "Consistency is key to seeing results.",
      "start_time": "66.8",
      "end_time": "69.9",
      "items": [121, 122, 123, 124, 125, 126]
    },
    {
      "id": 18,
      "transcript": "Thanks for watching! See you next time.",
      "start_time": "70.5",
      "end_time": "73.5",
      "items": [127, 128, 129, 130, 131, 132]
    }
  ]
});

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // home: VideoWithSubtitles(
      //   videoPath: "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
      //   subtitleData: subtitleJson,
      //   format: SubtitleFormat.json,
      // ),
      home: VideoWithTextOverlay(),
    ),
  );
}