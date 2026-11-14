#include <rm_control/client.hpp>
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <thread>

int main(int argc, char** argv) {
    using namespace rm_control;
    using Clock = std::chrono::steady_clock;
    std::string host="127.0.0.1", token, output="control-probe";
    int port=47650; double seconds=5; bool actions=false, ping_only=false;
    try {
        for (int i=1;i<argc;++i) {
            const std::string arg=argv[i];
            if (arg=="--actions") actions=true;
            else if (arg=="--ping-only") ping_only=true;
            else if (i+1<argc && arg=="--host") host=argv[++i];
            else if (i+1<argc && arg=="--port") port=std::stoi(argv[++i]);
            else if (i+1<argc && arg=="--token") token=argv[++i];
            else if (i+1<argc && arg=="--seconds") seconds=std::stod(argv[++i]);
            else if (i+1<argc && arg=="--output") output=argv[++i];
            else throw std::runtime_error("Usage: rm_control_probe --host IP --token TOKEN [--port 47650] [--seconds 5] [--actions] [--ping-only] [--output DIR]");
        }
        if (token.empty() || port<1 || port>65535 || seconds<=0) throw std::runtime_error("Token, port or duration missing/invalid");
        std::filesystem::create_directories(output);
        Client client; client.connect(host,static_cast<std::uint16_t>(port),token);
        std::vector<double> latencies; Json action_results=Json::array(), last_state;
        std::size_t frames=0, bytes=0; bool acted=false, reloaded=false;
        const auto start=Clock::now();
        while (std::chrono::duration<double>(Clock::now()-start).count()<seconds) {
            const auto before=Clock::now();
            if (ping_only) {
                last_state=client.ping().at("state");
                std::this_thread::sleep_for(std::chrono::milliseconds(33));
                continue;
            }
            auto frame=client.observe();
            latencies.push_back(std::chrono::duration<double,std::milli>(Clock::now()-before).count());
            ++frames; bytes+=frame.jpeg.size(); last_state=frame.state;
            if (frames==1) {
                std::ofstream file(std::filesystem::path(output)/"frame.jpg",std::ios::binary);
                file.write(reinterpret_cast<const char*>(frame.jpeg.data()),static_cast<std::streamsize>(frame.jpeg.size()));
                std::ofstream(std::filesystem::path(output)/"frame.json") << Json{{"width",frame.width},{"height",frame.height},
                    {"fx",frame.fx},{"fy",frame.fy},{"cx",frame.cx},{"cy",frame.cy},{"state",frame.state}}.dump(2);
            }
            if (actions && !acted && frame.state.at("phase")=="training" && !frame.state.at("paused").get<bool>() && frame.state.at("can_fire").get<bool>()) {
                auto result=client.act({frame.frame_id,frame.round_id,5,3,true});
                action_results.push_back(result);
                if (!result.value("ok",false) || !result.value("fired",false) || !result.value("look_applied",false))
                    throw std::runtime_error("Probe look/fire failed: "+result.dump());
                const auto& state=result.at("state");
                if (state.at("mag").get<int>() != frame.state.at("mag").get<int>()-1 ||
                    state.at("shot_count").get<int>() != frame.state.at("shot_count").get<int>()+1)
                    throw std::runtime_error("Probe shot did not update ammo/statistics once");
                acted=true;
            } else if (actions && acted && !reloaded && frame.state.at("phase")=="training") {
                auto result=client.reload(); action_results.push_back(result);
                if (!result.value("reloaded",false)) throw std::runtime_error("Probe reload failed: "+result.dump());
                reloaded=true;
            }
        }
        const double elapsed=std::chrono::duration<double>(Clock::now()-start).count();
        client.disconnect();
        if (actions && (!acted || !reloaded)) throw std::runtime_error("No active training round available for action probe");
        std::sort(latencies.begin(),latencies.end());
        double total=0; for (double value:latencies) total+=value;
        Json report{{"seconds",elapsed},{"frames",frames},{"frames_per_second",frames/elapsed},
                    {"bytes",bytes},{"mean_observe_ms",latencies.empty()?0:total/latencies.size()},
                    {"p95_observe_ms",latencies.empty()?0:latencies[std::min(latencies.size()-1,std::size_t(latencies.size()*0.95))]},
                    {"actions",action_results},{"last_state",last_state}};
        std::ofstream(std::filesystem::path(output)/"report.json") << report.dump(2);
        std::cout << "CPP PROBE PASS: " << frames << " frames, " << report["frames_per_second"] << " fps\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
