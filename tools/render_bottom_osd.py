"""Run the real OSD RTL on clean posters; keep simulation outputs outside sources."""
from pathlib import Path
import shutil
import subprocess
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
RTL=ROOT/'src/user_source/hdl_source'
WORK=ROOT/'verification/render'
ASSETS=ROOT/'assets/osd_bottom_20261008'

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    (WORK/'osd').mkdir(exist_ok=True)
    shutil.copyfile(RTL/'osd/osd_text.mem',WORK/'osd/osd_text.mem')
    for page in range(1,5):
        image=Image.open(ASSETS/f'tf_pages/P{page}.bmp').convert('RGB')
        (WORK/f'P{page}.mem').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in image.getdata()),encoding='ascii')
    cmd=['D:/iverlog/iverilog/bin/iverilog.exe','-g2012','-DOSD_SIM','-I',str(RTL),
         '-s','tb_bottom_osd_render','-o',str(WORK/'render.vvp'),
         str(ROOT/'verification/reference_tests/tb_bottom_osd_render.v'),str(RTL/'video_bottom_osd.v'),str(RTL/'osd/osd_bitmap_rom.v')]
    subprocess.run(cmd,check=True,cwd=WORK)
    proc=subprocess.run(['D:/iverlog/iverilog/bin/vvp.exe',str(WORK/'render.vvp')],cwd=WORK,text=True,capture_output=True)
    (WORK/'render.log').write_text(proc.stdout+proc.stderr,encoding='utf-8')
    print(proc.stdout);proc.check_returncode()
    target=ASSETS/'rtl_preview';target.mkdir(exist_ok=True)
    for name in ['P1','P2','P2_adjust','P3','P4']:
        image=Image.open(WORK/f'{name}.ppm');assert image.size==(640,480)
        image.save(target/f'{name}.png')
    assert Image.open(WORK/'P1.ppm').tobytes()==Image.open(ASSETS/'tf_pages/P1.bmp').convert('RGB').tobytes()
    print('PASS P1: every RTL output pixel equals the supplied clean startup image.')

if __name__=='__main__':main()
