#ifndef TLS_CLIENT_H
#define TLS_CLIENT_H

#include <string>
#include <functional>

struct TLSConfig {
    std::string host;
    int port;
    std::string caPath;
    std::string certPath;
    std::string keyPath;
};

class TLSClient {
public:
    TLSClient();
    ~TLSClient();

    bool connect(const TLSConfig& config);
    std::string send(const std::string& data);
    void close();
    bool isConnected() const;

private:
    bool connected_;
    TLSConfig config_;
    int64_t sessionId_;
};

#endif
