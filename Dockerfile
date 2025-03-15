# Gebruik de officiële Dart runtime
FROM dart:stable

# Stel de werkdirectory in
WORKDIR /app

# Kopieer pubspec.yaml en installeer dependencies
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# Kopieer de rest van de app
COPY . .

# Stel de serverpoort in
ENV PORT=8080

# Start de API
CMD ["dart", "server.dart"]
