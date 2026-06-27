FROM ghcr.io/cirruslabs/flutter:3.32.4

WORKDIR /app

COPY . /app

RUN flutter config --no-analytics \
    && flutter pub get

WORKDIR /app/sdk_compliance_adapter

EXPOSE 8080

CMD ["flutter", "test", "test/adapter_server_test.dart", "--reporter", "expanded"]
