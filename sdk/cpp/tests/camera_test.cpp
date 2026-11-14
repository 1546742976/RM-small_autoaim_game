#include <rm_control/client.hpp>
#include <cmath>
#include <iostream>
#include <stdexcept>
int main() {
    using namespace rm_control;
    Observation frame; frame.fx=500; frame.fy=500; frame.cx=640; frame.cy=360;
    frame.frame_id=8; frame.round_id=2;
    auto check=[](bool ok){ if (!ok) throw std::runtime_error("camera geometry mismatch"); };
    auto center=aim_at(frame,640,360); check(center.yaw_deg==0 && center.pitch_deg==0);
    auto right=aim_at(frame,1140,360); check(std::abs(right.yaw_deg-45)<1e-8 && right.pitch_deg==0);
    auto up=aim_at(frame,640,-140); check(std::abs(up.pitch_deg-45)<1e-8);
    // Reproject the chosen ray after nonzero camera pitch (including off-axis).
    for (double pitch:{-75.,-30.,0.,30.,75.}) {
        frame.state={{"pitch_deg",pitch}};
        for (double x:{500.,640.,780.}) for (double y:{250.,360.,470.}) {
            auto a=aim_at(frame,x,y,true); const double rad=3.14159265358979323846/180.;
            double dx=(x-640)/500,dy=(360-y)/500;
            double world_y=dy*std::cos(pitch*rad)+std::sin(pitch*rad);
            double forward=std::cos(pitch*rad)-dy*std::sin(pitch*rad);
            double length=std::sqrt(dx*dx+world_y*world_y+forward*forward);
            double new_pitch=(pitch+a.pitch_deg)*rad,yaw=a.yaw_deg*rad;
            check(std::abs(std::sin(yaw)*std::cos(new_pitch)-dx/length)<1e-8);
            check(std::abs(std::sin(new_pitch)-world_y/length)<1e-8);
            check(std::abs(std::cos(yaw)*std::cos(new_pitch)-forward/length)<1e-8);
            check(a.frame_id==8 && a.round_id==2 && a.fire);
        }
    }
    std::cout << "Camera geometry PASS (center, signs, 45 pitched rays)\n";
}
