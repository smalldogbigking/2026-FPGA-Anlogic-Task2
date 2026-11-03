"""Update the copied Keil project, retaining ST-Link Debug/Utilities settings."""
from pathlib import Path
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
mdk=root/'MDK-ARM'
for extension in ('uvprojx','uvoptx'):
    dest=mdk/f'RobotArmControl.{extension}'
    src=dest if dest.exists() else mdk/f'SixServoPickPlace.{extension}'
    tree=ET.parse(src)
    for node in tree.findall('.//TargetName'):node.text='RobotArm_Vision_Sort'
    for tag in ('FileName','FilePath','PathWithFileName','FilenameWithoutPath'):
        for node in tree.findall('.//'+tag):
            if node.text:node.text=node.text.replace('teach_receiver','motor_control')
    for node in tree.findall('.//GroupName'):
        if node.text=='SC1 Protocol':node.text='Motor core'
    if extension=='uvprojx':
        tree.find('.//OutputName').text='robot_arm_control'
        node=tree.find('.//Cads/VariousControls/IncludePath')
        node.text=r'..\App;..\Protocol;..\Calibration;..\Vision;..\Display;..\Drivers\CMSIS\Include;..\Drivers\Device\Include'
        groups=tree.find('.//Groups')
        existing={n.text for n in groups.findall('./Group/GroupName')}
        for name,files in {
            'Vision and batch control':['Vision/vision_protocol.c','Vision/pixel_map.c','Vision/robot_control.c','Vision/vision_config.h','Vision/robot_control.h'],
            'Smooth motion':['Protocol/motion_profile.c','Protocol/motion_profile.h'],
            'Single screen SSD1306':['Display/robot_display.c','Display/oled_ssd1306.c','Display/robot_display.h'],
        }.items():
            if name in existing:continue
            group=ET.SubElement(groups,'Group');ET.SubElement(group,'GroupName').text=name
            listing=ET.SubElement(group,'Files')
            for file in files:
                entry=ET.SubElement(listing,'File')
                ET.SubElement(entry,'FileName').text=Path(file).name
                ET.SubElement(entry,'FileType').text='1' if file.endswith('.c') else '5'
                ET.SubElement(entry,'FilePath').text='..\\'+file.replace('/','\\')
    ET.indent(tree,space='  ')
    tree.write(dest,encoding='utf-8',xml_declaration=True)
    if src!=dest:src.unlink() # only the two copied project descriptors
print(mdk/'RobotArmControl.uvprojx')
