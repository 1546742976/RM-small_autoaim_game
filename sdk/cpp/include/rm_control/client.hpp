#pragma once
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>

namespace rm_control {
using Json = nlohmann::json;
struct Observation {
    std::uint64_t frame_id{}, round_id{}, timestamp_us{};
    int width{}, height{};
    double fx{}, fy{}, cx{}, cy{};
    Json state = Json::object();
    std::vector<std::uint8_t> jpeg;
};
struct Action {
    std::uint64_t frame_id{}, round_id{};
    double yaw_deg{}, pitch_deg{}; // Right and up are positive.
    bool fire = false;
};
// Pinhole pixel-to-ray conversion. The vertical angle includes horizontal error.
Action aim_at(const Observation& frame, double pixel_x, double pixel_y, bool fire = false);

// Synchronous, one in-flight request. Not thread-safe. No action is retried.
// Call observe()/ping() at least once per second while idle; server timeout is 2s.
class Client {
public:
    Client();
    ~Client();
    Client(const Client&) = delete;
    Client& operator=(const Client&) = delete;
    void connect(const std::string& host, std::uint16_t port, const std::string& token);
    Observation observe();
    Json act(const Action& action);
    Json reload(); // Uses the last successful observation's context.
    Json ping();
    void disconnect();
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
    Json request(Json header, std::vector<std::uint8_t>* payload = nullptr);
};
}
