#include <rm_control/client.hpp>
#include <opencv2/core.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include <iostream>
#include <optional>

struct Detection { cv::Point2d head_pixel; bool request_fire=false; };
// Replace only this function with your detector. Input is BGR, no ground truth.
std::optional<Detection> detect_target(const cv::Mat& frame) {
    (void)frame;
    return std::nullopt;
}
int main(int argc,char** argv) {
    if (argc<3) {
        std::cerr << "Usage: rm_vision_template HOST TOKEN [PORT] [--no-window] [--frames=N]\n"; return 1;
    }
    try {
        int port=47650; bool display=true; std::size_t max_frames=0,decoded=0;
        for (int i=3;i<argc;++i) {
            if (std::string(argv[i])=="--no-window") display=false;
            else if (std::string(argv[i]).rfind("--frames=",0)==0) max_frames=std::stoull(std::string(argv[i]).substr(9));
            else port=std::stoi(argv[i]);
        }
        if (port<1 || port>65535) throw std::runtime_error("Invalid port");
        rm_control::Client client; client.connect(argv[1],static_cast<std::uint16_t>(port),argv[2]);
        while (!max_frames || decoded<max_frames) {
            const auto frame=client.observe();
            const cv::Mat bgr=cv::imdecode(frame.jpeg,cv::IMREAD_COLOR);
            if (bgr.empty() || bgr.cols!=frame.width || bgr.rows!=frame.height)
                throw std::runtime_error("Invalid camera image");
            ++decoded;
            if (display) {
                cv::imshow("RM camera - Escape disconnects",bgr);
                if (cv::waitKey(1)==27) break;
            }
            if (frame.state.at("phase")!="training" || frame.state.at("paused").get<bool>()) continue;
            const auto target=detect_target(bgr);
            if (!target) continue;
            if (target->head_pixel.x<0 || target->head_pixel.y<0 || target->head_pixel.x>=frame.width || target->head_pixel.y>=frame.height) continue;
            auto action=rm_control::aim_at(frame,target->head_pixel.x,target->head_pixel.y,
                target->request_fire && frame.state.at("can_fire").get<bool>());
            const auto result=client.act(action);
            if (!result.value("ok",false)) std::cerr << result.value("error","action rejected") << '\n';
            // Empty magazines auto-reload in game. Call client.reload() for an
            // earlier reload using the current observation; do not retry fire.
        }
        client.disconnect();
        std::cout << "VISION TEMPLATE: " << decoded << " decoded BGR frames\n";
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    return 0;
}
