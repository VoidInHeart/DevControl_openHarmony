#include "tls_client.h"
#include <cstdlib>
#include <sstream>

TLSClient::TLSClient() : connected_(false), sessionId_(0) {}

TLSClient::~TLSClient()
{
    close();
}

bool TLSClient::connect(const TLSConfig& config)
{
    config_ = config;
    sessionId_ = std::rand();
    connected_ = true;
    return true;
}

std::string TLSClient::send(const std::string& data)
{
    if (!connected_) {
        return "{\"result\":\"error\",\"message\":\"not connected\"}";
    }
    return "{\"result\":\"ok\",\"echo\":\"" + data + "\",\"sessionId\":" + std::to_string(sessionId_) + "}";
}

void TLSClient::close()
{
    connected_ = false;
    sessionId_ = 0;
}

bool TLSClient::isConnected() const
{
    return connected_;
}
