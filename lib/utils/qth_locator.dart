class QthLocator {
  static String calculate(double lat, double lon) {
    lon += 180.0;
    lat += 90.0;

    String locator = "";

    // Field (A-R)
    locator += String.fromCharCode(65 + (lon / 20).floor());
    locator += String.fromCharCode(65 + (lat / 10).floor());

    // Square (0-9)
    lon = lon % 20.0;
    lat = lat % 10.0;
    locator += String.fromCharCode(48 + (lon / 2).floor());
    locator += String.fromCharCode(48 + (lat / 1).floor());

    // Subsquare (A-X)
    lon = (lon % 2.0) * 12.0; 
    lat = (lat % 1.0) * 24.0;
    locator += String.fromCharCode(65 + lon.floor());
    locator += String.fromCharCode(65 + lat.floor());

    return locator;
  }
}
