import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Weather Pro',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const WeatherScreen(),
    );
  }
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> with TickerProviderStateMixin {
  final String apiKey = dotenv.env['OPENWEATHER_API_KEY'] ?? '';
  final TextEditingController searchController = TextEditingController();
  
  late final AnimationController _floatController;
  late final Stream<int> _timeStream;

  Map<String, dynamic>? weatherData;
  Map<String, dynamic>? forecastData;

  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    
    _timeStream = Stream.periodic(const Duration(seconds: 1), (count) => count).asBroadcastStream();
    
    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    getCurrentWeather();
  }

  @override
  void dispose() {
    searchController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> getCurrentWeather() async {
    try {
      setState(() {
        if (weatherData == null) {
          isLoading = true;
        }
        hasError = false;
        searchController.clear();
      });

      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception("Location Disabled");

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception("Permission Denied");
      }

      Position position = await Geolocator.getCurrentPosition();
      await fetchWeather(position.latitude, position.longitude);
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        setState(() {
          hasError = true;
          isLoading = false;
        });
      }
    }
  }

  Future<void> fetchWeather(double lat, double lon) async {
    try {
      final weatherUrl =
          "https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&units=metric&appid=$apiKey";
      final forecastUrl =
          "https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&units=metric&appid=$apiKey";

      final weatherResponse = await http.get(Uri.parse(weatherUrl)).timeout(const Duration(seconds: 10));
      final forecastResponse = await http.get(Uri.parse(forecastUrl)).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (weatherResponse.statusCode == 200 && forecastResponse.statusCode == 200) {
        weatherData = jsonDecode(weatherResponse.body);
        forecastData = jsonDecode(forecastResponse.body);
        setState(() {
          isLoading = false;
          hasError = false;
        });
      } else {
        throw Exception("API Error Response received: ${weatherResponse.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network Error: Please check your connection.")),
      );
    }
  }

  Future<void> searchCity(String city) async {
    try {
      setState(() {
        isLoading = true;
      });

      final weatherUrl =
          "https://api.openweathermap.org/data/2.5/weather?q=$city&units=metric&appid=$apiKey";
      final forecastUrl =
          "https://api.openweathermap.org/data/2.5/forecast?q=$city&units=metric&appid=$apiKey";

      final weatherResponse = await http.get(Uri.parse(weatherUrl)).timeout(const Duration(seconds: 10));
      final forecastResponse = await http.get(Uri.parse(forecastUrl)).timeout(const Duration(seconds: 10));
      
      if (!mounted) return;

      final weather = jsonDecode(weatherResponse.body);

      if (weather["cod"] != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid location. Please try again.")),
        );
        setState(() {
          isLoading = false;
        });
        return;
      }

      weatherData = weather;
      forecastData = jsonDecode(forecastResponse.body);

      setState(() {
        isLoading = false;
        hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasError = true;
      });
    }
  }

  List<Map<String, dynamic>> getDailyForecast() {
    if (forecastData == null || forecastData!["list"] == null) return [];
    
    final List forecastList = forecastData!["list"];
    final Map<String, Map<String, dynamic>> dailyMap = {};
    final int offset = weatherData!["timezone"] ?? 0;

    for (var item in forecastList) {
      final int dt = item["dt"];
      final DateTime date = DateTime.fromMillisecondsSinceEpoch(dt * 1000, isUtc: true).add(Duration(seconds: offset));
      final String dayKey = DateFormat("yyyy-MM-dd").format(date);
      
      if (!dailyMap.containsKey(dayKey)) {
        dailyMap[dayKey] = Map<String, dynamic>.from(item);
        dailyMap[dayKey]!["date_obj"] = date; 
      } else {
        if (item["main"]["temp"] > dailyMap[dayKey]!["main"]["temp"]) {
          dailyMap[dayKey]!["main"]["temp"] = item["main"]["temp"];
          dailyMap[dayKey]!["weather"][0] = item["weather"][0];
        }
      }
    }
    return dailyMap.values.take(5).toList();
  }

  bool isDarkBackground() {
    if (weatherData == null) return true; 
    final icon = weatherData!["weather"][0]["icon"].toString();
    final condition = weatherData!["weather"][0]["main"].toString().toLowerCase();

    if (icon.endsWith("n")) return true;
    
    if (condition == "rain" || condition == "thunderstorm" || condition == "snow" || condition == "drizzle") {
      return true;
    }
    
    return false; 
  }

  Color get primaryTextColor => isDarkBackground() ? Colors.white : Colors.black87;
  Color get secondaryTextColor => isDarkBackground() ? Colors.white.withOpacity(0.85) : Colors.black.withOpacity(0.7);
  List<Shadow> get textShadows => [
        Shadow(
          color: isDarkBackground() ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.8),
          blurRadius: 4,
          offset: const Offset(1, 1),
        )
      ];

  Color getOverlayColor() {
    if (weatherData == null) return Colors.black54;
    final condition = weatherData!["weather"][0]["main"].toString().toLowerCase();

    switch (condition) {
      case "clear": return Colors.orange.withOpacity(0.1);
      case "rain": return Colors.blue.withOpacity(0.25);
      case "clouds": return Colors.grey.withOpacity(0.15);
      case "thunderstorm": return Colors.deepPurple.withOpacity(0.35);
      default: return Colors.black38;
    }
  }

  String getBackgroundImage() {
    if (weatherData == null) {
      return "https://images.pexels.com/photos/912110/pexels-photo-912110.jpeg";
    }

    final condition = weatherData!["weather"][0]["main"].toString().toLowerCase();
    final icon = weatherData!["weather"][0]["icon"];
    
    final int offset = weatherData!["timezone"] ?? 0;
    final hour = DateTime.now().toUtc().add(Duration(seconds: offset)).hour;

    if (hour >= 5 && hour < 7) {
      return "https://images.pexels.com/photos/189349/pexels-photo-189349.jpeg";
    }
    if (hour >= 17 && hour < 19) {
      return "https://images.pexels.com/photos/799443/pexels-photo-799443.jpeg";
    }

    if (icon.endsWith("n")) {
      switch (condition) {
        case "clear": return "https://images.pexels.com/photos/355465/pexels-photo-355465.jpeg";
        case "clouds": return "https://images.pexels.com/photos/414659/pexels-photo-414659.jpeg";
        case "rain": return "https://images.pexels.com/photos/110874/pexels-photo-110874.jpeg";
        case "thunderstorm": return "https://images.pexels.com/photos/1118869/pexels-photo-1118869.jpeg";
        default: return "https://images.pexels.com/photos/355465/pexels-photo-355465.jpeg";
      }
    }

    switch (condition) {
      case "clear": return "https://images.pexels.com/photos/912110/pexels-photo-912110.jpeg";
      case "clouds": return "https://images.pexels.com/photos/531756/pexels-photo-531756.jpeg";
      case "rain": return "https://images.pexels.com/photos/110874/pexels-photo-110874.jpeg";
      case "snow": return "https://images.pexels.com/photos/688660/pexels-photo-688660.jpeg";
      case "thunderstorm": return "https://images.pexels.com/photos/1162251/pexels-photo-1162251.jpeg";
      default: return "https://images.pexels.com/photos/912110/pexels-photo-912110.jpeg";
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgImg = getBackgroundImage();
    final bool isDark = isDarkBackground();

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  child: Image.network(
                    bgImg,
                    key: ValueKey(bgImg),
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        getOverlayColor(), 
                        isDark ? Colors.black.withOpacity(0.85) : Colors.black.withOpacity(0.3)
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: RefreshIndicator(
                  color: isDark ? Colors.white : Colors.black,
                  backgroundColor: isDark ? Colors.black45 : Colors.white70,
                  onRefresh: getCurrentWeather,
                  child: isLoading
                      ? ListView( 
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: constraints.maxHeight * 0.8,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        )
                      : hasError
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 200),
                                Center(
                                  child: Text("Unable To Load Weather Data", 
                                    style: TextStyle(color: primaryTextColor, fontSize: 16, shadows: textShadows))),
                              ],
                            )
                          : buildDynamicWeatherUI(constraints),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: getCurrentWeather,
        backgroundColor: isDark ? Colors.white24 : Colors.black87,
        elevation: 0,
        icon: Icon(Icons.my_location, color: isDark ? Colors.white : Colors.white),
        label: Text("Location", style: TextStyle(color: isDark ? Colors.white : Colors.white)),
      ),
    );
  }

  Widget buildLiveClock(int timezoneOffset) {
    return StreamBuilder<int>(
      stream: _timeStream, 
      builder: (context, snapshot) {
        final DateTime localCityTime = DateTime.now().toUtc().add(Duration(seconds: timezoneOffset));
        final String timeString = DateFormat("hh:mm:ss a").format(localCityTime);
        final String dateString = DateFormat("EEEE, MMM d").format(localCityTime);
        
        final duration = Duration(seconds: timezoneOffset);
        final hours = duration.inHours;
        final minutes = (duration.inMinutes.abs() % 60);
        final offsetString = 'GMT${hours >= 0 ? '+' : ''}$hours:${minutes.toString().padLeft(2, '0')}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              timeString,
              style: TextStyle(color: primaryTextColor, fontSize: 28, fontWeight: FontWeight.bold, shadows: textShadows),
            ),
            const SizedBox(height: 2),
            Text(
              "$dateString • $offsetString",
              style: TextStyle(color: secondaryTextColor, fontSize: 14, fontWeight: FontWeight.w600, shadows: textShadows),
            ),
          ],
        );
      },
    );
  }

  Widget buildDynamicWeatherUI(BoxConstraints constraints) {
    final city = weatherData!["name"];
    final icon = weatherData!["weather"][0]["icon"];
    final description = weatherData!["weather"][0]["description"];
    final temp = weatherData!["main"]["temp"];
    final feelsLike = weatherData!["main"]["feels_like"];
    
    final tempMin = weatherData!["main"]["temp_min"].toDouble();
    final tempMax = weatherData!["main"]["temp_max"].toDouble();
    final double visibilityKm = (weatherData!["visibility"] ?? 0) / 1000;
    final int windDeg = weatherData!["wind"]["deg"] ?? 0;
    final int cloudCoverage = weatherData!["clouds"]["all"] ?? 0;

    final double currentWidth = constraints.maxWidth;
    final bool isSmallScreen = currentWidth < 360;
    
    final double paddingHorizontal = currentWidth * 0.05;
    final double mainIconSize = isSmallScreen ? 100 : 130;
    final double tempFontSize = isSmallScreen ? 65 : 75;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 14),
      children: [
        buildLiveClock(weatherData!["timezone"] ?? 0),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.location_on, color: primaryTextColor, size: 22, shadows: textShadows),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                city,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: primaryTextColor, fontSize: isSmallScreen ? 22 : 26, fontWeight: FontWeight.bold, shadows: textShadows),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Center(
          child: Container( 
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(horizontal: 4), 
            child: TextField(
              controller: searchController,
              textAlign: TextAlign.center,
              style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: "Search City",
                hintStyle: TextStyle(color: secondaryTextColor),
                filled: true,
                fillColor: isDarkBackground() ? Colors.black.withOpacity(0.35) : Colors.white.withOpacity(0.4),
                prefixIcon: Icon(Icons.search, color: primaryTextColor, size: 22),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: isDarkBackground() ? Colors.white.withOpacity(0.25) : Colors.black.withOpacity(0.15), 
                    width: 1.2
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: isDarkBackground() ? Colors.white70 : Colors.black87, 
                    width: 1.5
                  ),
                ),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) searchCity(value.trim());
              },
            ),
          ),
        ),
        const SizedBox(height: 6),

        Center(
          child: AnimatedBuilder(
            animation: _floatController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatController.value * -10 + 2),
                child: child,
              );
            },
            child: Image.network(
              "https://openweathermap.org/img/wn/$icon@4x.png",
              width: mainIconSize,
              height: mainIconSize,
              gaplessPlayback: true,
            ),
          ),
        ),

        Center(
          child: Text(
            "${temp.round()}°",
            style: TextStyle(color: primaryTextColor, fontSize: tempFontSize, fontWeight: FontWeight.bold, height: 0.9, shadows: textShadows),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            toBeginningOfSentenceCase(description) ?? "",
            style: TextStyle(color: primaryTextColor, fontSize: isSmallScreen ? 16 : 19, fontWeight: FontWeight.w600, shadows: textShadows),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            "Feels Like ${feelsLike.round()}°  •  High: ${tempMax.round()}°  Low: ${tempMin.round()}°",
            style: TextStyle(color: secondaryTextColor, fontSize: 14, fontWeight: FontWeight.w600, shadows: textShadows),
          ),
        ),
        const SizedBox(height: 16),

        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            child: buildGlassCard(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: weatherInfo(Icons.water_drop, "Humidity", "${weatherData!["main"]["humidity"]}%", isSmallScreen)),
                      buildDivider(),
                      Expanded(child: weatherInfo(Icons.air, "Wind", "${weatherData!["wind"]["speed"]} m/s", isSmallScreen)),
                      buildDivider(),
                      Expanded(child: weatherInfo(Icons.explore, "Direction", "$windDeg°", isSmallScreen)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: weatherInfo(Icons.visibility, "Visibility", "${visibilityKm.toStringAsFixed(1)} km", isSmallScreen)),
                      buildDivider(),
                      Expanded(child: weatherInfo(Icons.speed, "Pressure", "${weatherData!["main"]["pressure"]} hPa", isSmallScreen)),
                      buildDivider(),
                      Expanded(child: weatherInfo(Icons.cloud, "Clouds", "$cloudCoverage%", isSmallScreen)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            child: buildSunCard(isSmallScreen),
          ),
        ),
        const SizedBox(height: 12),

        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: buildVisualHourlyForecast(currentWidth), 
          ),
        ),
        const SizedBox(height: 22),

        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: buildForecastSection(currentWidth), 
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget buildDivider() {
    return Container(
      width: 1, 
      height: 28, 
      color: isDarkBackground() ? Colors.white24 : Colors.black12
    );
  }

  Widget weatherInfo(IconData icon, String title, String value, bool isSmall) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: isSmall ? 18 : 20, color: secondaryTextColor),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: isSmall ? 11 : 13, color: secondaryTextColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmall ? 13 : 15, color: primaryTextColor)),
      ],
    );
  }

  Widget buildSunCard(bool isSmall) {
    if (weatherData == null || weatherData!["sys"] == null) return const SizedBox.shrink();
    final sunrise = weatherData!["sys"]["sunrise"] ?? 0;
    final sunset = weatherData!["sys"]["sunset"] ?? 0;
    final int offset = weatherData!["timezone"] ?? 0;

    final sunriseTime = DateFormat("hh:mm a").format(
      DateTime.fromMillisecondsSinceEpoch(sunrise * 1000, isUtc: true).add(Duration(seconds: offset)),
    );
    final sunsetTime = DateFormat("hh:mm a").format(
      DateTime.fromMillisecondsSinceEpoch(sunset * 1000, isUtc: true).add(Duration(seconds: offset)),
    );

    return buildGlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wb_sunny, color: isDarkBackground() ? Colors.orangeAccent : Colors.orange.shade700, size: isSmall ? 21 : 24),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Sunrise", style: TextStyle(color: secondaryTextColor, fontSize: isSmall ? 11 : 13, fontWeight: FontWeight.w600)),
                  Text(sunriseTime, style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: isSmall ? 13 : 15)),
                ],
              ),
            ],
          ),
          buildDivider(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.nightlight_round, color: isDarkBackground() ? Colors.blueAccent : Colors.blue.shade800, size: isSmall ? 19 : 22),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Sunset", style: TextStyle(color: secondaryTextColor, fontSize: isSmall ? 11 : 13, fontWeight: FontWeight.w600)),
                  Text(sunsetTime, style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: isSmall ? 13 : 15)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildVisualHourlyForecast(double screenWidth) {
    if (forecastData == null || forecastData!["list"] == null) return const SizedBox.shrink();
    final List forecastList = forecastData!["list"];
    if (forecastList.isEmpty) return const SizedBox.shrink();

    List<Map<String, dynamic>> interpolatedHourly = [];
    
    for (int i = 0; i < forecastList.length - 1 && interpolatedHourly.length < 24; i++) {
      final current = forecastList[i];
      final next = forecastList[i + 1];
      
      interpolatedHourly.add(current);
      if (interpolatedHourly.length >= 24) break;

      Map<String, dynamic> hour1 = Map<String, dynamic>.from(current);
      hour1["dt"] = current["dt"] + 3600; 
      hour1["main"] = Map<String, dynamic>.from(current["main"]);
      hour1["main"]["temp"] = current["main"]["temp"] + (next["main"]["temp"] - current["main"]["temp"]) / 3.0;
      hour1["pop"] = (current["pop"] ?? 0) + (((next["pop"] ?? 0) - (current["pop"] ?? 0)) / 3.0);
      interpolatedHourly.add(hour1);
      if (interpolatedHourly.length >= 24) break;

      Map<String, dynamic> hour2 = Map<String, dynamic>.from(current);
      hour2["dt"] = current["dt"] + 7200; 
      hour2["main"] = Map<String, dynamic>.from(current["main"]);
      hour2["main"]["temp"] = current["main"]["temp"] + (next["main"]["temp"] - current["main"]["temp"]) * (2.0 / 3.0);
      hour2["pop"] = (current["pop"] ?? 0) + (((next["pop"] ?? 0) - (current["pop"] ?? 0)) * (2.0 / 3.0));
      interpolatedHourly.add(hour2);
    }

    List<FlSpot> spots = [];
    for (int i = 0; i < interpolatedHourly.length; i++) {
      final temp = interpolatedHourly[i]["main"]["temp"].toDouble();
      spots.add(FlSpot(i.toDouble(), temp));
    }

    final dynamicTileWidth = (screenWidth * 0.16).clamp(54.0, 74.0);
    final dynamicFontSize = (screenWidth * 0.03).clamp(10.0, 12.0);
    final dynamicIconSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final int offset = weatherData!["timezone"] ?? 0;
    
    final bool isDark = isDarkBackground();

    final double tileTotalWidth = dynamicTileWidth + 8.0; 
    final double totalScrollWidth = interpolatedHourly.length * tileTotalWidth;
    final double chartPadding = tileTotalWidth / 2.0; 

    return buildGlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hourly Forecast",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
          ),
          const SizedBox(height: 16),
          
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: totalScrollWidth, 
              child: Column(
                children: [
                  Container(
                    height: 95, 
                    padding: EdgeInsets.symmetric(horizontal: chartPadding), 
                    child: LineChart(
                      LineChartData(
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            tooltipRoundedRadius: 8,
                            tooltipMargin: 12, 
                            fitInsideHorizontally: true, 
                            fitInsideVertically: true, 
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((LineBarSpot touchedSpot) {
                                return LineTooltipItem(
                                  '${touchedSpot.y.round()}°',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    height: 1.1, 
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            barWidth: 2.5,
                            color: isDark ? Colors.orange.shade400 : Colors.blueGrey.shade800,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  Row(
                    children: List.generate(interpolatedHourly.length, (index) {
                      final item = interpolatedHourly[index];
                      final int itemTime = item["dt"];
                      
                      final DateTime date = DateTime.fromMillisecondsSinceEpoch(itemTime * 1000, isUtc: true).add(Duration(seconds: offset));
                      final timeStr = DateFormat("h a").format(date).toLowerCase();

                      final int displayTemp = (item["main"]["temp"] as num).round();
                      final int displayPop = (((item["pop"] ?? 0) as num) * 100).round();
                      final String hourlyIcon = item["weather"]?[0]?["icon"] ?? "01d";

                      return Container(
                        width: dynamicTileWidth,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        margin: const EdgeInsets.symmetric(horizontal: 4), 
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.05)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(timeStr, textAlign: TextAlign.center, style: TextStyle(fontSize: dynamicFontSize, color: secondaryTextColor, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Image.network(
                              "https://openweathermap.org/img/wn/$hourlyIcon.png",
                              width: dynamicIconSize, 
                              height: dynamicIconSize,
                              errorBuilder: (_, __, ___) => Icon(Icons.cloud, size: dynamicIconSize * 0.6, color: secondaryTextColor),
                            ),
                            Text("$displayPop%", textAlign: TextAlign.center, style: TextStyle(fontSize: dynamicFontSize - 1.0, color: isDark ? Colors.blueAccent : Colors.blue.shade700, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text("$displayTemp°", textAlign: TextAlign.center, style: TextStyle(fontSize: dynamicFontSize + 2.0, fontWeight: FontWeight.bold, color: primaryTextColor)),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildForecastSection(double screenWidth) {
    final dailyList = getDailyForecast();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, 
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: Text(
            "5-Day Forecast",
            style: TextStyle(color: primaryTextColor, fontSize: 20, fontWeight: FontWeight.bold, shadows: textShadows),
          ),
        ),
        SizedBox(
          height: 150, 
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(dailyList.length, (index) {
                  return forecastTile(dailyList[index], screenWidth);
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget forecastTile(Map<String, dynamic> item, double screenWidth) {
    final icon = item["weather"][0]["icon"];
    final condition = item["weather"][0]["main"];
    final DateTime dateObj = item["date_obj"];
    final day = DateFormat("E").format(dateObj);
    final temp = item["main"]["temp"].round();
    final rainProbability = ((item["pop"] ?? 0) * 100).round();

    final dynamicTileWidth = (screenWidth * 0.25).clamp(84.0, 114.0);
    final dynamicTitleSize = (screenWidth * 0.035).clamp(12.0, 14.0);
    final dynamicIconSize = (screenWidth * 0.07).clamp(24.0, 32.0);
    
    final bool isDark = isDarkBackground();

    return Container(
      width: dynamicTileWidth,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: buildGlassCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(day, style: TextStyle(fontSize: dynamicTitleSize, fontWeight: FontWeight.bold, color: primaryTextColor)),
            Image.network(
              "https://openweathermap.org/img/wn/$icon.png",
              width: dynamicIconSize, 
              height: dynamicIconSize,
              gaplessPlayback: true,
            ),
            Text("$temp°", style: TextStyle(fontSize: dynamicTitleSize + 3.0, fontWeight: FontWeight.bold, color: primaryTextColor)),
            const SizedBox(height: 2),
            Text("$rainProbability% Rain", style: TextStyle(fontSize: dynamicTitleSize - 2.0, color: isDark ? Colors.blueAccent : Colors.blue.shade700, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              condition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dynamicTitleSize - 2.0, color: secondaryTextColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    final bool isDark = isDarkBackground();
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(16), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          padding: padding ?? const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                ? [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.04)]
                : [Colors.black.withOpacity(0.08), Colors.black.withOpacity(0.02)],
            ),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.12)
            ),
          ),
          child: child,
         ),
      ),
    );
  }
}