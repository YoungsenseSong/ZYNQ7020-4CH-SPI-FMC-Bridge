"""MC004 regression and independent byte/block checks. Outputs must be new."""
import argparse, binascii, csv, hashlib, json, shutil, struct, subprocess, time, zlib
from pathlib import Path
PROJECT=Path(__file__).resolve().parents[1]
WORKSPACE=PROJECT.parents[2]
PROTOCOL=PROJECT.parent.parent/'protocol'
COMMAND=['rtl/common/cdc_sync.v','rtl/spi/spi_record_parser.v','rtl/spi/spi_fixed_transaction_master.v','rtl/spi/ch0_spi_controller.v']
CAPTURE=COMMAND+['rtl/fifo/record_fifo_bram.v','rtl/scheduler/four_channel_record_mux.v','rtl/top/four_channel_capture_core.v']
BRIDGE=CAPTURE+['rtl/block/block_builder.v','rtl/block/block_pingpong_bram.v','rtl/top/four_channel_bridge_core.v']

def vectors(out):
    base=(PROTOCOL/'golden/nrf_record_valid.bin').read_bytes()
    assert len(base)==248
    for ch in range(4):
        records=[]
        for n,seq in enumerate((0xfffffffe,0xffffffff,0,1)):
            r=bytearray(base);r[5]=ch+1
            struct.pack_into('<IIQQ',r,8,seq,1,1000+ch*73+n*100,n*32)
            r[40:244]=bytes((ch*131+n*37+i*11)&255 for i in range(204))
            struct.pack_into('<H',r,38,binascii.crc_hqx(r[:38],0xffff))
            struct.pack_into('<I',r,244,zlib.crc32(r[40:244]));records.append(r)
        (out/f'channel{ch}.bin').write_bytes(b''.join(records))

def capture_check(out,name,channels):
    expected={ch:(out/f'channel{ch}.bin').read_bytes() for ch in range(channels)}
    assembled={}
    for row in csv.DictReader((out/name).open(newline='')):
        run,ch,rec,offset=(int(row[k]) for k in ('run','channel','record','offset'))
        assert run in (0,2) and ch in expected and 0<=rec<4,row
        b=assembled.setdefault((run,ch,rec),bytearray());assert offset==len(b),row;b.append(int(row['data'],16))
    assert set(assembled)=={(run,ch,rec) for run in (0,2) for ch in range(channels) for rec in range(4)}
    for (run,ch,rec),b in assembled.items(): assert b==expected[ch][rec*248:(rec+1)*248],(run,ch,rec)
    return {'records':len(assembled),'bytes':sum(map(len,assembled.values())),'runs':[0,2]}

def block_check(out):
    blocks={}
    for row in csv.DictReader((out/'blocks.csv').open(newline='')):
        n,offset=int(row['block']),int(row['offset']);b=blocks.setdefault(n,bytearray())
        assert offset==len(b),row;b.append(int(row['data'],16))
    assert set(blocks)==set(range(4))
    received=[0]*4
    for seq,b in blocks.items():
        assert len(b)==1056 and b[:4]==b'FPB1'
        version,header=struct.unpack_from('<HH',b,4);assert version==1 and header==64
        assert struct.unpack_from('<II',b,8)==(seq,1)
        payload_size=struct.unpack_from('<I',b,16)[0];assert payload_size==992
        payload=b[64:];assert zlib.crc32(payload)==struct.unpack_from('<I',b,60)[0]
        counts=[0]*4
        for offset in range(0,len(payload),248):
            r=payload[offset:offset+248];ch=r[5]-1;assert 0<=ch<4
            expected=(out/f'channel{ch}.bin').read_bytes()[received[ch]*248:(received[ch]+1)*248]
            assert r==expected,(seq,ch,received[ch]);received[ch]+=1;counts[ch]+=1
            assert binascii.crc_hqx(r[:38],0xffff)==struct.unpack_from('<H',r,38)[0]
            assert zlib.crc32(r[40:244])==struct.unpack_from('<I',r,244)[0]
        assert tuple(counts)==struct.unpack_from('<IIII',b,40)
        assert struct.unpack_from('<I',b,20)[0]==sum(1<<ch for ch,c in enumerate(counts) if c)
    assert received==[4]*4
    return {'blocks':4,'records':16,'bytes':sum(map(len,blocks.values())),'channel_records':received,'block_and_record_crc':'PASS'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--iverilog',default='iverilog');parser.add_argument('--vvp',default='vvp');args=parser.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);vectors(out)
    tools={k:shutil.which(getattr(args,k)) for k in ('iverilog','vvp')}
    if not all(tools.values()):raise RuntimeError('Icarus required')
    common_args=[f'+GOLDEN_DIR={(PROTOCOL/"golden").as_posix()}',f'+MC_GOLDEN_DIR={out.as_posix()}']
    tests=[
        ('tb_four_channel_record_mux',['rtl/scheduler/four_channel_record_mux.v'],[]),
        ('tb_record_fifo_bram',['rtl/fifo/record_fifo_bram.v'],[]),
        ('tb_block_pingpong_bram',['rtl/block/block_pingpong_bram.v'],[]),
        ('tb_four_channel_capture_core',CAPTURE+['sim/two_channel_spi_slave_model.sv'],[f'+MC_CAPTURE={(out/"capture_four.csv").as_posix()}']),
        ('tb_four_channel_bridge_core',BRIDGE+['sim/two_channel_spi_slave_model.sv'],[f'+MC_BLOCK_CAPTURE={(out/"blocks.csv").as_posix()}']),
        ('tb_two_channel_record_mux',['rtl/scheduler/two_channel_record_mux.v'],[]),
        ('tb_two_channel_capture_core',COMMAND+['rtl/scheduler/two_channel_record_mux.v','rtl/top/two_channel_capture_core.v','sim/two_channel_spi_slave_model.sv'],[f'+MC_CAPTURE={(out/"capture_two.csv").as_posix()}']),
        ('tb_spi_record_parser',['rtl/spi/spi_record_parser.v'],[]),
        ('tb_block_builder',['rtl/block/block_builder.v'],[]),
        ('tb_bram_pingpong',['rtl/block/bram_pingpong.v'],[]),
        ('tb_four_channel_record_aligner',['rtl/alignment/four_channel_record_aligner.v'],[]),
        ('tb_ch0_record_aligner',['rtl/alignment/four_channel_record_aligner.v'],[]),
        ('tb_ch0_spi_controller',COMMAND[1:],[])]
    commands=[];used={Path(__file__).resolve(),PROJECT/'rtl/common/protocol_defs.vh'}
    def run(label,command,marker=None):
        print('RUN '+label,flush=True);start=time.monotonic()
        result=subprocess.run(list(map(str,command)),cwd=PROJECT,capture_output=True,text=True,errors='replace',timeout=180)
        log=result.stdout+result.stderr;(out/(label+'.log')).write_text(log,encoding='utf-8')
        commands.append({'name':label,'command':list(map(str,command)),'cwd':str(PROJECT),'exit_code':result.returncode,'seconds':round(time.monotonic()-start,3)})
        (out/'commands.json').write_text(json.dumps(commands,indent=2))
        if result.returncode or marker and marker not in log:raise RuntimeError(label+' failed\n'+log[-3000:])
        print('PASS '+label,flush=True)
    for name,sources,plus in tests:
        paths=[PROJECT/('sim/'+name+'.sv')]+[PROJECT/s for s in sources];used.update(paths);exe=out/(name+'.vvp')
        run(name+'_compile',[tools['iverilog'],'-g2012','-Wall','-I',PROJECT/'rtl/common','-s',name,'-o',exe]+paths)
        run(name,[tools['vvp'],exe]+common_args+plus,name.upper()+'_OK')
    summary={'status':'PASS','rtl_tests':len(tests),'four_capture':capture_check(out,'capture_four.csv',4),
        'two_capture':capture_check(out,'capture_two.csv',2),'blocks':block_check(out),'tools':tools,
        'boundary':'RTL/digital SPI models; no RF, Zephyr DMA, physical timing or board execution'}
    used.update((PROTOCOL/'golden').glob('*'))
    hashes={str(p.relative_to(WORKSPACE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(used) if p.is_file()}
    (out/'input_sha256.json').write_text(json.dumps(hashes,indent=2));(out/'summary.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
