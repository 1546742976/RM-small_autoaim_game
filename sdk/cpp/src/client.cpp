#include <rm_control/client.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
using Socket = SOCKET;
static constexpr Socket invalid_socket = INVALID_SOCKET;
static void close_socket(Socket s) { closesocket(s); }
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/tcp.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
using Socket = int;
static constexpr Socket invalid_socket = -1;
static void close_socket(Socket s) { close(s); }
#endif

namespace rm_control {
struct Client::Impl {
    Socket socket = invalid_socket;
    std::uint64_t id = 0, frame_id = 0, round_id = 0;
    void close() {
        if (socket != invalid_socket) close_socket(socket);
        socket = invalid_socket;
        frame_id = round_id = 0;
    }
};

static void wait_socket(Socket socket, bool writing) {
    fd_set set; FD_ZERO(&set); FD_SET(socket, &set);
    timeval timeout{1, 500000};
    const int result = select(static_cast<int>(socket + 1), writing ? nullptr : &set,
                             writing ? &set : nullptr, nullptr, &timeout);
    if (result <= 0) throw std::runtime_error("Network timeout or socket error; request is NOT retried");
}
static void send_all(Socket socket, const std::uint8_t* data, std::size_t length) {
    while (length) {
        wait_socket(socket, true);
#ifdef _WIN32
        const int flags = 0;
#else
        const int flags = MSG_NOSIGNAL;
#endif
        const auto count = send(socket, reinterpret_cast<const char*>(data),
                                static_cast<int>(std::min<std::size_t>(length, 65536)), flags);
        if (count <= 0) throw std::runtime_error("Connection closed during send; outcome may be unknown");
        data += count; length -= static_cast<std::size_t>(count);
    }
}
static void receive_all(Socket socket, std::uint8_t* data, std::size_t length) {
    while (length) {
        wait_socket(socket, false);
        const auto count = recv(socket, reinterpret_cast<char*>(data),
                                static_cast<int>(std::min<std::size_t>(length, 65536)), 0);
        if (count <= 0) throw std::runtime_error("Connection closed during receive; outcome may be unknown");
        data += count; length -= static_cast<std::size_t>(count);
    }
}

Client::Client() : impl_(std::make_unique<Impl>()) {
#ifdef _WIN32
    WSADATA data;
    if (WSAStartup(MAKEWORD(2,2), &data) != 0) throw std::runtime_error("WSAStartup failed");
#endif
}
Client::~Client() {
    impl_->close();
#ifdef _WIN32
    WSACleanup();
#endif
}
void Client::connect(const std::string& host, std::uint16_t port, const std::string& token) {
    impl_->close();
    addrinfo hints{}; hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
    addrinfo* addresses = nullptr;
    if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &addresses) != 0)
        throw std::runtime_error("Cannot resolve server IPv4 address");
    for (auto a = addresses; a; a = a->ai_next) {
        Socket s = ::socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (s == invalid_socket) continue;
        // Nonblocking connect bounds unreachable-host waits to 1.5 seconds.
#ifdef _WIN32
        u_long enabled = 1; ioctlsocket(s, FIONBIO, &enabled);
#else
        const int previous = fcntl(s, F_GETFL, 0); fcntl(s, F_SETFL, previous | O_NONBLOCK);
#endif
        ::connect(s, a->ai_addr, static_cast<int>(a->ai_addrlen));
        bool success = false;
        try {
            wait_socket(s, true);
            int error = 0;
#ifdef _WIN32
            int size = sizeof(error);
#else
            socklen_t size = sizeof(error);
#endif
            success = getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error), &size) == 0 && error == 0;
        } catch (...) {}
        if (success) {
#ifdef _WIN32
            enabled = 0; ioctlsocket(s, FIONBIO, &enabled);
#else
            fcntl(s, F_SETFL, previous);
#endif
            int enabled_no_delay = 1;
            setsockopt(s, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<char*>(&enabled_no_delay), sizeof(enabled_no_delay));
            impl_->socket = s; break;
        }
        close_socket(s);
    }
    freeaddrinfo(addresses);
    if (impl_->socket == invalid_socket) throw std::runtime_error("Cannot connect to game");
    impl_->id = 0;
    try {
        auto reply = request({{"type","hello"},{"token",token}});
        if (!reply.value("ok", false)) throw std::runtime_error(reply.value("error", "handshake failed"));
    } catch (...) { impl_->close(); throw; }
}
Json Client::request(Json header, std::vector<std::uint8_t>* payload) {
    if (impl_->socket == invalid_socket) throw std::runtime_error("Client is disconnected");
    try {
        header["v"] = 1; header["id"] = ++impl_->id; header["payload_bytes"] = 0;
        const auto text = header.dump();
        const std::uint32_t length = static_cast<std::uint32_t>(text.size());
        std::uint8_t prefix[4]{static_cast<std::uint8_t>(length>>24),static_cast<std::uint8_t>(length>>16),
                               static_cast<std::uint8_t>(length>>8),static_cast<std::uint8_t>(length)};
        send_all(impl_->socket, prefix, 4);
        send_all(impl_->socket, reinterpret_cast<const std::uint8_t*>(text.data()), text.size());
        receive_all(impl_->socket, prefix, 4);
        const std::uint32_t size = (std::uint32_t(prefix[0])<<24)|(std::uint32_t(prefix[1])<<16)|
                                   (std::uint32_t(prefix[2])<<8)|prefix[3];
        if (size < 2 || size > 16384) throw std::runtime_error("Invalid response header length");
        std::string response(size, '\0');
        receive_all(impl_->socket, reinterpret_cast<std::uint8_t*>(response.data()), size);
        auto reply = Json::parse(response);
        if (reply.at("v") != 1 || reply.at("id") != impl_->id) throw std::runtime_error("Response version/id mismatch");
        const auto bytes = reply.at("payload_bytes").get<std::int64_t>();
        if (bytes < 0 || bytes > 8*1024*1024) throw std::runtime_error("Invalid image length");
        std::vector<std::uint8_t> image(static_cast<std::size_t>(bytes));
        receive_all(impl_->socket, image.data(), image.size());
        if (payload) *payload = std::move(image);
        else if (bytes) throw std::runtime_error("Unexpected binary payload");
        return reply;
    } catch (...) { impl_->close(); throw; }
}
Observation Client::observe() {
    Observation result;
    const auto reply = request({{"type","observe"}}, &result.jpeg);
    if (!reply.value("ok", false)) throw std::runtime_error(reply.value("error", "observe failed"));
    result.frame_id = reply.at("frame_id"); result.round_id = reply.at("round_id");
    result.timestamp_us = reply.at("timestamp_us");
    result.width = reply.at("width"); result.height = reply.at("height");
    const auto& camera = reply.at("camera");
    result.fx = camera.at("fx"); result.fy = camera.at("fy");
    result.cx = camera.at("cx"); result.cy = camera.at("cy"); result.state = reply.at("state");
    impl_->frame_id = result.frame_id; impl_->round_id = result.round_id;
    return result;
}
Json Client::act(const Action& action) {
    if (!std::isfinite(action.yaw_deg) || !std::isfinite(action.pitch_deg))
        throw std::invalid_argument("Angles must be finite");
    return request({{"type","act"},{"frame_id",action.frame_id},{"round_id",action.round_id},
                    {"yaw_deg",action.yaw_deg},{"pitch_deg",action.pitch_deg},{"fire",action.fire}});
}
Json Client::reload() {
    return request({{"type","reload"},{"frame_id",impl_->frame_id},{"round_id",impl_->round_id}});
}
Json Client::ping() { return request({{"type","ping"}}); }
void Client::disconnect() {
    if (impl_->socket == invalid_socket) return;
    try { request({{"type","disconnect"}}); } catch (...) { impl_->close(); throw; }
    impl_->close();
}
Action aim_at(const Observation& frame, double x, double y, bool fire) {
    if (!(frame.fx > 0 && frame.fy > 0) || !std::isfinite(x) || !std::isfinite(y))
        throw std::invalid_argument("Invalid camera intrinsics or pixel");
    constexpr double degrees = 180.0 / 3.14159265358979323846;
    const double dx = (x-frame.cx)/frame.fx, dy = (frame.cy-y)/frame.fy;
    // Transform the observed ray through the frame's pitch before solving yaw.
    const double pitch = frame.state.value("pitch_deg",0.0) / degrees;
    const double world_y = dy*std::cos(pitch) + std::sin(pitch);
    const double forward = std::cos(pitch) - dy*std::sin(pitch);
    return {frame.frame_id,frame.round_id,std::atan2(dx,forward)*degrees,
            std::atan2(world_y,std::hypot(dx,forward))*degrees-pitch*degrees,fire};
}
}
