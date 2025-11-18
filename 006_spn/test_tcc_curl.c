#include <stdio.h>
#include <curl/curl.h>

int main() {
    CURL *curl = curl_easy_init();
    if (curl) {
        printf("Hello from TCC! curl version: %s\n", curl_version());
        curl_easy_cleanup(curl);
    }
    return 0;
}
