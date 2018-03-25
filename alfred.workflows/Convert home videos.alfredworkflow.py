from __future__ import print_function
import sys, os, ntpath, time

def main(args):
    start_time = time.time()
    totalFiles = len(args)
    i = 1
    for file in args:
        log('Processing file [%s]', str(file))
        notify('Conversion process',
               'File %d of %d' % (i,totalFiles),
               'Processing [%s]' % ntpath.basename(file))
        if (os.path.isfile(file)):
           os.system("""
               /usr/local/bin/ffmpeg -y -i "{}" -c:v libx264 -crf 23 -c:a aac -b:a 192k "{}"
               """ \
               .format(file, os.path.splitext(file)[0]+'.264.mp4'))
        i+=1

    notify('Conversion process finished',
           'Processed %d files' % totalFiles,
           'Time spent %s' % time.strftime("%H:%M:%S",time.gmtime(time.time() - start_time)))

def notify(title, subtitle, message):
    os.system("""
        osascript -e 'display notification "{}" with title "{}" subtitle "{}"'
        """.format(message, title, subtitle))

def log(s, *args):
    if args:
        s = s % args
    print(s, file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv)<2:
        log('Have no files to convert')
    else:
        main(sys.argv[1:])
