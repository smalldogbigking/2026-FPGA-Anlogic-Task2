"""Compare programmer/SWD/flash settings with the supplied original project."""
from pathlib import Path
import xml.etree.ElementTree as ET
import json,hashlib,re,sys

root=Path(__file__).resolve().parents[1]
package=root.parent/'自动抓放V3_完整交接包_20261026-184430'/'ArmPickPlace_V3_Handoff_20261026-184430'/'six_servo_pickplace'
reference=root/'Reference/original_download_config.json'
sections={
    'uvprojx':[
        './/TargetCommonOption/Device','.//TargetCommonOption/Vendor','.//TargetCommonOption/PackID',
        './/TargetCommonOption/Cpu','.//TargetCommonOption/FlashDriverDll','.//DllOption','.//DebugOption',
        './/Utilities','.//TargetArmAds/ArmAdsMisc','.//TargetArmAds/LDads'],
    'uvoptx':['.//TargetOption/CLKADS','.//TargetOption/OPTTT','.//DebugOpt','.//TargetDriverDllRegistry'],
}
def canonical(node):
    if node is None:raise ValueError('Missing download configuration node')
    return [node.tag,sorted(node.attrib.items()),(node.text or '').strip(),[canonical(c) for c in node]]
def snapshot(folder,stem):
    result={}
    for ext,paths in sections.items():
        tree=ET.parse(folder/f'{stem}.{ext}')
        result[ext]={p:canonical(tree.find(p)) for p in paths}
    return result
if (package/'MDK-ARM/SixServoPickPlace.uvprojx').exists():
    original=snapshot(package/'MDK-ARM','SixServoPickPlace')
    if reference.exists():assert json.loads(reference.read_text(encoding='utf-8'))==original,'Original reference was changed'
    else:reference.write_text(json.dumps(original,indent=2,ensure_ascii=False),encoding='utf-8')
else:
    original=json.loads(reference.read_text(encoding='utf-8'))
if '--restore' in sys.argv:
    def materialize(value):
        tag,attrs,text,children=value
        node=ET.Element(tag,dict(attrs));node.text=text or None
        for child in children:node.append(materialize(child))
        return node
    for ext,values in original.items():
        path=root/'MDK-ARM'/f'RobotArmControl.{ext}';tree=ET.parse(path)
        for xpath,value in values.items():
            old=tree.find(xpath)
            if old is None:raise ValueError(xpath)
            for parent in tree.iter():
                if old in list(parent):
                    index=list(parent).index(old);parent.remove(old);parent.insert(index,materialize(value));break
        ET.indent(tree,space='  ');tree.write(path,encoding='utf-8',xml_declaration=True)
current=snapshot(root/'MDK-ARM','RobotArmControl')
assert current==original,'Download/debug/flash/memory configuration differs from the original project'
main=(root/'App/main.c').read_text()
assert 'USART1' not in main and 'USART_CR1_TE' not in main,'PC UART/TX still enabled'
assert 'pin(GPIOB,10' not in main and 'pin(GPIOA,9' not in main and 'pin(GPIOA,10' not in main
expected=[('2','1','0'),('2','2','1'),('2','3','2'),('2','4','3'),('3','1','4'),('3','2','5')]
def pwm_bindings(text):return re.findall(r'TIM(\d)->CCR(\d)\s*=\s*(?:p|pulse)\[(\d)\]',text)
assert pwm_bindings(main)==expected,'PWM mapping changed'
if (package/'App/main.c').exists():assert pwm_bindings((package/'App/main.c').read_text())==expected
assert 'const unsigned pins[]={0,1,2,3,6,7}' in main
assert 'timer->PSC=63' in main and 'BOARD_PWM_PERIOD_US-1' in main
report=dict(download_configuration_identical=True,sections_compared=sum(map(len,sections.values())),
            pwm_pins_unchanged=['PA0','PA1','PA2','PA3','PA6','PA7'],pc_control_removed=True,uart_transmit_disabled=True,
            reference_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),downloaded=False)
(root/'tests/download_config_check.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('PASS: original ST-Link/SWD/flash/reset/memory settings identical; six PWM pins unchanged; PC UART removed.')
